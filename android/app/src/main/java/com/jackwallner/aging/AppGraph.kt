package com.jackwallner.aging

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.aging.data.AuthService
import com.jackwallner.aging.data.CareStore
import com.jackwallner.aging.data.Cloud
import com.jackwallner.aging.data.FilePersistence
import com.jackwallner.aging.data.GroupService
import com.jackwallner.aging.data.KeyValueStore
import com.jackwallner.aging.data.ReminderService
import com.jackwallner.aging.data.SharedPreferencesStore
import com.jackwallner.aging.data.StoreService
import com.jackwallner.aging.data.SyncCoordinator
import java.io.File
import kotlinx.coroutines.MainScope

/** Every shared object, built once per process. */
class AppGraph(context: Context) {
    val defaults: KeyValueStore = SharedPreferencesStore(context)
    val care = CareStore(FilePersistence(File(context.filesDir, "care.json")))
    val store = StoreService(context.applicationContext, defaults)
    val reminders = ReminderService(context.applicationContext, care, defaults)

    /** Supabase in every shipped build. Debug launch options may swap in the in-memory fake before first use. */
    var cloud: Cloud = Cloud.supabase(defaults)
    val auth = AuthService { cloud }
    val groups = GroupService(defaults, care, auth, { cloud })
    val sync = SyncCoordinator(care, auth, groups, { cloud })
    val scope = MainScope()

    /** An invitation code from a tapped link, waiting for the join screen to take it. */
    var pendingInviteCode by mutableStateOf<String?>(null)

    /** Joined from a link before any record existed: the circle's record arrives by sync, nothing is asked. */
    fun finishJoinOnboarding() {
        care.update { it.copy(hasCompletedOnboarding = true) }
        pendingInviteCode = null
    }

    /** Plus on this phone, or Plus bought by anyone in the circle (`group_billing`). */
    val isPlus: Boolean get() = store.isPro || groups.hasPlus

    init {
        // Any change to people or medications re-plans the reminders.
        care.onChange = { reminders.refresh() }
        // A change the family should see goes out a moment later, not on the next launch.
        care.onQueued = { sync.schedule(scope) }
    }

    /**
     * Sign-out and account deletion: the shared record comes off this phone
     * (a wipe, never a delete sent to the family), the RevenueCat customer is
     * released, and reminders re-plan from what is left. Private records stay.
     */
    suspend fun signOutAndForget() {
        auth.signOut()
        groups.forgetGroupLocally()
        store.forgetCustomer()
    }

    /** Network-free: the cached session and circle, so first paint never waits on a server. */
    fun bootstrap() {
        auth.bootstrap()
        groups.loadFromCache()
    }

    /** After the UI is up: refresh the session, the circle, then sync. Every step tolerates no signal. */
    suspend fun refreshFromServer() {
        auth.refreshInBackground()
        if (!auth.isSignedIn) return
        groups.refresh()
        // Not only a Sharing concern: this is what applies a narrowed access scope to the local copy.
        groups.loadMembers()
        sync.syncNow()
    }
}

class AgingApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
