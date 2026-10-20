package com.jackwallner.aging.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jackwallner.aging.AgingApplication
import com.jackwallner.aging.MainActivity
import com.jackwallner.aging.R
import com.jackwallner.aging.model.DoseReminderPlanner
import com.jackwallner.aging.model.ReminderSpec
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Per-person reminder switch, same key shape as iOS (`dose-reminders.<id>`). Off until turned on. */
class ReminderPreferences(private val defaults: KeyValueStore) {
    fun isEnabled(personId: UUID) = defaults.getBoolean(key(personId))

    fun setEnabled(personId: UUID, enabled: Boolean) =
        if (enabled) defaults.putBoolean(key(personId), true) else defaults.remove(key(personId))

    fun enabledPeople(ids: Collection<UUID>): Set<UUID> = ids.filter(::isEnabled).toSet()

    private fun key(personId: UUID) = "dose-reminders.${personId.toString().uppercase()}"
}

/**
 * Dose reminders on Android: one rolling alarm for the soonest grouped
 * reminder. When it fires, every reminder due at that minute is posted and the
 * next alarm is set. `setWindow` keeps it inexact (no exact-alarm permission or
 * Play declaration), within a few minutes of the dose time.
 */
class ReminderService(
    private val context: Context,
    private val care: CareStore,
    private val defaults: KeyValueStore,
    val preferences: ReminderPreferences = ReminderPreferences(defaults),
) {

    fun canPost(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun currentPlan(now: Instant = Instant.now()): List<ReminderSpec> {
        val state = care.state
        return DoseReminderPlanner.plan(state, preferences.enabledPeople(state.people.map { it.id }), now)
    }

    /** Re-plans from the record; call after any change to people, medications or the switch. */
    fun refresh(now: Instant = Instant.now()) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarmIntent()
        alarms.cancel(pending)
        val next = DoseReminderPlanner.next(currentPlan(now), now, ZoneId.systemDefault()) ?: return
        alarms.setWindow(AlarmManager.RTC_WAKEUP, next.first.toEpochMilli(), WINDOW_MS, pending)
    }

    /** Posts every reminder due since the last firing (each once), then sets the next alarm. */
    fun fire(firedAt: Instant = Instant.now()) {
        val zone = ZoneId.systemDefault()
        val lastFire = Instant.ofEpochMilli(defaults.getLong(LAST_FIRE, 0))
        // The alarm may arrive up to the window late: look back that far, but never past the last delivery.
        val dueAfter = maxOf(lastFire, firedAt.minusMillis(WINDOW_MS + 60_000))
        val until = firedAt.plusSeconds(60)
        val due = DoseReminderPlanner.due(currentPlan(dueAfter), dueAfter, until, zone)
        if (canPost()) due.forEach(::post)
        defaults.putLong(LAST_FIRE, until.toEpochMilli())
        refresh(until)
    }

    private fun post(spec: ReminderSpec) {
        ensureChannel()
        val open = PendingIntent.getActivity(
            context, spec.identifier.hashCode(),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_PERSON, spec.personId.toString()),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(spec.title)
            .setContentText(spec.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(spec.body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(spec.identifier.hashCode(), notification)
        } catch (_: SecurityException) {
            // Permission withdrawn between the check and the post: nothing to deliver.
        }
    }

    private fun ensureChannel() {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Dose reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "A notification at each scheduled dose time for the people you turn reminders on for."
            },
        )
    }

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, ReminderReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        const val CHANNEL = "dose-reminders"
        const val ACTION_FIRE = "com.jackwallner.aging.REMINDER"
        const val EXTRA_PERSON = "personId"
        const val WINDOW_MS = 5 * 60_000L
        private const val LAST_FIRE = "dose-reminders.lastFire"
    }
}

/** Fires the rolling alarm, and re-plans after a reboot, update or clock change. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminders = (context.applicationContext as AgingApplication).graph.reminders
        if (intent.action == ReminderService.ACTION_FIRE) reminders.fire() else reminders.refresh()
    }
}
