package com.jackwallner.aging

import com.jackwallner.aging.data.AccessScope
import com.jackwallner.aging.data.AuthService
import com.jackwallner.aging.data.Billing
import com.jackwallner.aging.data.CareStore
import com.jackwallner.aging.data.GroupError
import com.jackwallner.aging.data.GroupRole
import com.jackwallner.aging.data.GroupService
import com.jackwallner.aging.data.HttpResponse
import com.jackwallner.aging.data.HttpTransport
import com.jackwallner.aging.data.InMemoryStore
import com.jackwallner.aging.data.InviteFailure
import com.jackwallner.aging.data.InviteLink
import com.jackwallner.aging.data.InviteMessage
import com.jackwallner.aging.data.KeyValueSessionStore
import com.jackwallner.aging.data.MemoryPersistence
import com.jackwallner.aging.data.PaidBoundary
import com.jackwallner.aging.data.SupabaseClient
import com.jackwallner.aging.data.SupabaseConfig
import com.jackwallner.aging.data.SupabaseError
import com.jackwallner.aging.data.SupabaseSyncRemote
import com.jackwallner.aging.data.SyncCoordinator
import com.jackwallner.aging.data.SyncFailure
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.SyncEntity
import com.jackwallner.aging.model.SyncPage
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Port of the invitation rules in `InviteLinkTests.swift`. */
class InviteLinkTest {
    @Test fun aDictatedCodeIsNormalized() {
        assertEquals("HKT7PQ2M", InviteLink.normalized("hkt7 pq2m"))
        assertEquals("HKT7PQ2M", InviteLink.normalized("HKT7-PQ2M"))
        assertNull(InviteLink.normalized("HKT7PQ2"))
    }

    @Test fun bothAddressesCarryTheCodeAndNothingElseDoes() {
        assertEquals("HKT7PQ2M", InviteLink.code("https", "jackwallner.com", "/ios/elderhub/join.html", "hkt7pq2m"))
        assertEquals("HKT7PQ2M", InviteLink.code("elderhub", "invite", "", "HKT7PQ2M"))
        assertNull(InviteLink.code("https", "jackwallner.com", "/ios/elderhub/", "HKT7PQ2M"))
        assertNull(InviteLink.code("elderhub", "auth", "", "HKT7PQ2M"))
        assertNull(InviteLink.code("mailto", null, null, "HKT7PQ2M"))
    }

    @Test fun theMessageLeadsWithTheHttpsLinkAndIsNotIphoneOnly() {
        val text = InviteMessage.text("HKT7PQ2M", GroupRole.CAREGIVER, null)
        assertTrue(text.contains("https://jackwallner.com/ios/elderhub/join.html?code=HKT7PQ2M"))
        assertFalse(text.contains("elderhub://"))
        assertFalse(text.contains("iPhone"))
        assertTrue(InviteMessage.text("HKT7PQ2M", GroupRole.SUBJECT, "Eleanor").contains("links you to Eleanor care record"))
    }

    @Test fun emailMatchesTheServerRuleAndEscapesTheBody() {
        assertTrue(InviteLink.isValidEmail(" Sarah+mom@Example.com "))
        assertFalse(InviteLink.isValidEmail("sarah@example"))
        val uri = InviteMessage.emailUri("sarah+mom@example.com", "HKT7PQ2M", GroupRole.CAREGIVER, null)!!
        assertTrue(uri.startsWith("mailto:sarah%2Bmom%40example.com?subject=Invitation%20to%20join%20Elderhub&body="))
        assertFalse(uri.substringAfter("body=").contains("&"))
        assertNull(InviteMessage.emailUri("not an address", "HKT7PQ2M", GroupRole.CAREGIVER, null))
    }
}

/** The session rules from `AuthService.swift`, over a scripted transport. */
class SupabaseClientTest {
    private class Script(vararg replies: Any) : HttpTransport {
        val queue = replies.toMutableList()
        val sent = mutableListOf<Triple<String, String, String?>>()
        val headers = mutableListOf<Map<String, String>>()
        override suspend fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
            sent += Triple(method, url, body)
            this.headers += headers
            return when (val next = queue.removeAt(0)) {
                is HttpResponse -> next
                is IOException -> throw next
                else -> error("bad script")
            }
        }
    }

    private fun sessionJson(user: String = "11111111-1111-4111-8111-111111111111", name: String = "") =
        JSONObject().put("access_token", "a").put("refresh_token", "r").put("expires_in", 3600)
            .put("user", JSONObject().put("id", user).put("user_metadata", JSONObject().put("full_name", name))).toString()

    @Test fun googleIdTokenIsExchangedWithTheRawNonce() = runBlocking {
        val script = Script(HttpResponse(200, sessionJson(name = "Jack Wallner")))
        val client = SupabaseClient(KeyValueSessionStore(InMemoryStore()), script)
        val session = client.signInWithIdToken("google", "token", "raw-nonce")
        val (method, url, body) = script.sent.single()
        assertEquals("POST", method)
        assertEquals("${SupabaseConfig.AUTH}/token?grant_type=id_token", url)
        val json = JSONObject(body!!)
        assertEquals("google", json.getString("provider"))
        assertEquals("raw-nonce", json.getString("nonce"))
        assertEquals(SupabaseConfig.PUBLISHABLE_KEY, script.headers.single()["apikey"])
        assertEquals("Jack Wallner", session.displayName)
    }

    @Test fun theSessionIsReadBackWithNoNetwork() = runBlocking {
        val values = InMemoryStore()
        SupabaseClient(KeyValueSessionStore(values), Script(HttpResponse(200, sessionJson()))).signInWithIdToken("google", "t", "n")
        val relaunched = SupabaseClient(KeyValueSessionStore(values), Script())
        assertEquals("11111111-1111-4111-8111-111111111111", relaunched.session!!.userId)
    }

    @Test fun aTransportFailureOrA5xxNeverSignsAnyoneOut() = runBlocking {
        val values = InMemoryStore()
        SupabaseClient(KeyValueSessionStore(values), Script(HttpResponse(200, sessionJson()))).signInWithIdToken("google", "t", "n")
        val client = SupabaseClient(KeyValueSessionStore(values), Script(IOException("no route"), HttpResponse(503, "{\"message\":\"upstream\"}")))
        runCatching { client.refresh() }
        runCatching { client.refresh() }
        assertTrue(client.session != null)
    }

    @Test fun onlyADefinitiveRejectionSignsOut() = runBlocking {
        val values = InMemoryStore()
        SupabaseClient(KeyValueSessionStore(values), Script(HttpResponse(200, sessionJson()))).signInWithIdToken("google", "t", "n")
        val rejected = HttpResponse(400, "{\"code\":400,\"error_code\":\"refresh_token_not_found\",\"msg\":\"Invalid Refresh Token\"}")
        val client = SupabaseClient(KeyValueSessionStore(values), Script(rejected))
        try {
            client.refresh()
            fail("expected a revocation")
        } catch (_: SupabaseError.SessionRevoked) {
        }
        assertNull(client.session)
        assertNull(KeyValueSessionStore(values).load())
    }

    @Test fun postgrestCodesAreReadAndAnRlsRefusalIsARejection() = runBlocking {
        val values = InMemoryStore()
        SupabaseClient(KeyValueSessionStore(values), Script(HttpResponse(200, sessionJson()))).signInWithIdToken("google", "t", "n")
        val refused = HttpResponse(403, "{\"code\":\"42501\",\"message\":\"new row violates row-level security policy\"}")
        val remote = SupabaseSyncRemote(SupabaseClient(KeyValueSessionStore(values), Script(refused, IOException("offline"))))
        try {
            remote.push(SyncEntity.PERSON, JSONObject().put("id", UUID.randomUUID().toString()))
            fail()
        } catch (e: SyncFailure.Rejected) {
            assertTrue(e.message!!.contains("row-level security"))
        }
        try {
            remote.pull(SyncEntity.PERSON, UUID.randomUUID(), null, 10)
            fail()
        } catch (_: SyncFailure.Offline) {
        }
    }

    @Test fun thePullAsksStrictlyAfterTheCompoundCursor() = runBlocking {
        val values = InMemoryStore()
        SupabaseClient(KeyValueSessionStore(values), Script(HttpResponse(200, sessionJson()))).signInWithIdToken("google", "t", "n")
        val script = Script(HttpResponse(200, "[]"))
        val group = UUID.fromString("22222222-2222-4222-8222-222222222222")
        val id = UUID.fromString("33333333-3333-4333-8333-333333333333")
        SupabaseSyncRemote(SupabaseClient(KeyValueSessionStore(values), script))
            .pull(SyncEntity.MEDICATION, group, SyncPage(Instant.parse("2026-10-21T09:12:33.123456Z"), id), 200)
        val url = java.net.URLDecoder.decode(script.sent.single().second, "UTF-8")
        assertTrue(url, url.contains("medications?select=*&group_id=eq.$group"))
        assertTrue(url, url.contains("or=(updated_at.gt.2026-10-21T09:12:33.123456Z,and(updated_at.eq.2026-10-21T09:12:33.123456Z,id.gt.$id))"))
        assertTrue(url, url.endsWith("order=updated_at.asc,id.asc&limit=200"))
    }
}

/** Port of the circle rules in `GroupServiceTests.swift`, against the debug fake backend. */
class GroupServiceTest {
    private val server = FakeCareServer()
    private val values = InMemoryStore()
    private val care = CareStore(MemoryPersistence())
    private val auth = AuthService { server.cloud() }
    private val groups = GroupService(values, care, auth, { server.cloud() })
    private val sync = SyncCoordinator(care, auth, groups, { server.cloud() })

    private fun signIn() = runBlocking {
        server.signInWithIdToken("google", "t", "n")
        auth.bootstrap()
        groups.loadFromCache()
    }

    @Test fun startingACircleMovesWhatIsOnThePhoneIntoIt() = runBlocking {
        val mom = Person(name = "Eleanor")
        care.upsertPerson(mom)
        care.upsertMedication(Medication(personId = mom.id, name = "Lisinopril"))
        signIn()
        val id = groups.createGroup("Eleanor's care circle")
        assertEquals(GroupRole.OWNER, groups.role)
        assertEquals(id, care.state.person(mom.id)!!.groupId)
        sync.syncNow()
        assertEquals(1, server.tables.getValue(SyncEntity.PERSON).size)
        assertEquals(1, server.tables.getValue(SyncEntity.MEDICATION).size)
        assertTrue(sync.lastSyncedAt != null)
    }

    @Test fun joiningAdoptsNothingAndPullsTheFamilysRecord() = runBlocking {
        val mine = Person(name = "My own record", isSelf = true)
        care.upsertPerson(mine)
        val code = server.seedSarahsCircle()
        signIn()
        groups.acceptInvite(code.lowercase())
        assertEquals("Eleanor's care circle", groups.groupName)
        assertEquals(GroupRole.CAREGIVER, groups.role)
        sync.syncNow()
        assertEquals(setOf("My own record", "Eleanor Wallner"), care.state.people.map { it.name }.toSet())
        assertNull(care.state.person(mine.id)!!.groupId)
        assertTrue(server.tables.getValue(SyncEntity.PERSON).values.none { it.getString("name") == "My own record" })
        // The check-in time the server stamped is on the pulled record.
        assertTrue(care.state.people.first { it.name == "Eleanor Wallner" }.lastCheckInAt != null)
    }

    @Test fun aBadCodeSaysWhatToDoNext() = runBlocking {
        signIn()
        try {
            groups.acceptInvite("ZZZZZZZZ")
            fail()
        } catch (e: GroupError) {
            assertEquals(InviteFailure.INVALID_CODE.message, e.message)
        }
    }

    @Test fun aCircleWithARecordInItIsNotSwappedForAnInvitation() = runBlocking {
        signIn()
        val mom = Person(name = "Eleanor")
        care.upsertPerson(mom)
        groups.createGroup("Mine")
        care.upsertMedication(Medication(personId = mom.id, name = "Lisinopril"))
        sync.syncNow()
        val code = server.seedSarahsCircle()
        try {
            groups.acceptInvite(code)
            fail()
        } catch (e: GroupError) {
            assertEquals(InviteFailure.ALREADY_IN_GROUP.message, e.message)
        }
    }

    @Test fun membersAreCachedForAnOfflineLaunch() = runBlocking {
        signIn()
        val id = groups.createGroup("Circle")
        server.addSibling(id)
        groups.loadMembers()
        assertEquals(listOf("You", "Michael Wallner"), groups.members.map { it.resolvedName })
        server.isOnline = false
        val relaunched = GroupService(values, care, auth, { server.cloud() })
        relaunched.loadFromCache()
        relaunched.loadMembers()
        assertEquals(2, relaunched.members.size)
        assertTrue(relaunched.hasSharedWithFamily)
    }

    @Test fun restrictingAccessRemovesTheOtherRecordsLocallyAndNeverDeletesThemForTheFamily() = runBlocking {
        val code = server.seedSarahsCircle()
        signIn()
        groups.acceptInvite(code)
        sync.syncNow()
        val groupId = groups.activeGroupId!!
        // Sarah adds Dad, then narrows this account to Mom only.
        val dad = UUID.randomUUID()
        server.touch(SyncEntity.PERSON, JSONObject().put("id", dad.toString()).put("group_id", groupId.toString()).put("name", "Robert"))
        sync.syncNow()
        assertEquals(2, care.state.people.size)
        val me = server.session!!.userId.let(UUID::fromString)
        server.members.first { it.userId == me }.scope = AccessScope.LISTED
        server.grants += me to UUID.fromString("00000000-0000-4000-8000-0000000d0004")
        groups.loadMembers()
        assertEquals(listOf("Eleanor Wallner"), care.state.people.map { it.name })
        assertTrue(care.state.sync.outbox.isEmpty())
        assertTrue(server.tables.getValue(SyncEntity.PERSON)[dad]!!.isNull("deleted_at"))
    }

    @Test fun leavingWipesTheSharedCopyButKeepsPrivateRecords() = runBlocking {
        val mine = Person(name = "Private")
        care.upsertPerson(mine)
        val code = server.seedSarahsCircle()
        signIn()
        groups.acceptInvite(code)
        sync.syncNow()
        groups.leaveGroup()
        assertNull(groups.activeGroupId)
        assertEquals(listOf("Private"), care.state.people.map { it.name })
        assertTrue(care.state.sync.outbox.isEmpty())
        assertTrue(server.tables.getValue(SyncEntity.PERSON).values.all { it.isNull("deleted_at") })
    }

    @Test fun theCirclesPlusUnlocksASiblingWhoDidNotPay() = runBlocking {
        val code = server.seedSarahsCircle()
        signIn()
        groups.acceptInvite(code)
        assertFalse(groups.hasPlus)
        server.billingRows[groups.activeGroupId!!] = Billing("plus", Instant.now().plusSeconds(86_400), false)
        groups.refreshBilling()
        assertTrue(groups.hasPlus)
        assertTrue(PaidBoundary.canAddPerson(groups.hasPlus, 1))
        server.billingRows[groups.activeGroupId!!] = Billing("plus", Instant.now().minusSeconds(60), false)
        groups.refreshBilling()
        assertFalse(groups.hasPlus)
        server.billingRows[groups.activeGroupId!!] = Billing("plus", null, true)
        groups.refreshBilling()
        assertTrue(groups.hasPlus)
    }

    @Test fun thePersonBeingLookedAfterSeesTheTransparencyPageBeforeAnythingSyncs() = runBlocking {
        signIn()
        val id = groups.createGroup("Circle")
        val mom = Person(name = "Eleanor")
        care.upsertPerson(mom)
        val code = groups.generateInviteCode(GroupRole.SUBJECT, mom.id, null)
        sync.syncNow()
        // Mom signs in on her own phone with her own account.
        val momServerView = server
        momServerView.signInAs = FakeCareServer.User(UUID.randomUUID(), "Eleanor")
        val momValues = InMemoryStore()
        val momCare = CareStore(MemoryPersistence())
        val momAuth = AuthService { server.cloud() }
        val momGroups = GroupService(momValues, momCare, momAuth, { server.cloud() })
        val momSync = SyncCoordinator(momCare, momAuth, momGroups, { server.cloud() })
        server.signInWithIdToken("google", "t", "n")
        momAuth.bootstrap()
        momGroups.acceptInvite(code)
        assertEquals(GroupRole.SUBJECT, momGroups.role)
        assertTrue(momGroups.requiresTransparency)
        momSync.syncNow()
        assertTrue(momCare.state.people.isEmpty())
        momGroups.markTransparencyAccepted()
        momSync.syncNow()
        assertEquals(listOf("Eleanor"), momCare.state.people.map { it.name })
        assertEquals(id, momGroups.activeGroupId)
    }

    @Test fun signingInWithGoogleNamesTheAccountWithoutAskingAgain() = runBlocking {
        server.signInWithIdToken("google", "t", "n")
        auth.bootstrap()
        auth.updateDisplayName("Jack Wallner")
        assertEquals("Jack Wallner", server.users.values.single().name)
        assertEquals("Jack Wallner", server.session!!.displayName)
    }
}
