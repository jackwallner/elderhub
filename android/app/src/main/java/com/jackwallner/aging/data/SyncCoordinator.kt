package com.jackwallner.aging.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Drives the [SyncEngine] from the UI layer, port of `SyncCoordinator.swift`.
 * Foreground only, like iOS: sync is allowed to be late, never lossy. A local
 * change queues a cycle a moment later so a sibling sees a dose without a
 * pull-to-refresh, and the app runs one on every foreground.
 */
class SyncCoordinator(
    private val care: CareStore,
    private val auth: AuthService,
    private val groups: GroupService,
    private val cloud: () -> Cloud,
    private val clock: () -> Instant = Instant::now,
) {
    val engine = SyncEngine(care, clock)

    var isSyncing by mutableStateOf(false)
        private set
    var lastSyncedAt by mutableStateOf<Instant?>(null)
        private set
    /** Why the last cycle did not finish. Reported in Settings, never in front of the record (I1). */
    var lastError by mutableStateOf<String?>(null)
        private set
    var isOffline by mutableStateOf(false)
        private set

    val conflictCount: Int get() = care.state.sync.conflictCount
    val pendingCount: Int get() = care.state.sync.pendingCount

    private var scheduled: Job? = null

    /** Called when a local write queued something. Coalesces a burst of edits into one cycle. */
    fun schedule(scope: CoroutineScope, delayMillis: Long = 1_500) {
        if (!canSync) return
        scheduled?.cancel()
        scheduled = scope.launch {
            delay(delayMillis)
            syncNow()
        }
    }

    private val canSync: Boolean
        get() = auth.isSignedIn && groups.activeGroupId != null && !groups.requiresTransparency

    suspend fun syncNow() {
        if (isSyncing || !canSync) return
        val groupId = groups.activeGroupId ?: return
        isSyncing = true
        try {
            apply(engine.sync(cloud().sync, groupId))
        } finally {
            isSyncing = false
        }
    }

    /**
     * Folds one cycle into the published state. Only a cycle that completed moves
     * "last synced", the rule whose absence hid a total sync failure on iOS for two builds.
     */
    fun apply(outcome: SyncEngine.Outcome) {
        lastError = outcome.failure
        isOffline = outcome.wasOffline
        if (outcome.isComplete) lastSyncedAt = clock()
    }

    fun adoptPerson(personId: UUID) {
        val groupId = groups.activeGroupId ?: return
        care.adoptPerson(personId, groupId)
    }

    fun conflicts() = engine.conflicts()

    suspend fun resolveKeepingLocal(id: UUID) {
        engine.resolveKeepingLocal(id)
        syncNow()
    }

    suspend fun resolveTakingRemote(id: UUID) {
        engine.resolveTakingRemote(id)
        syncNow()
    }
}
