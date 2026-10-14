package com.apex.vaulty.vaulty

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * The phone's calendars for lib/services/calendar_service.dart: reads events to
 * import, and keeps Vaulty's own calendar in step with dated items.
 *
 * Vaulty's calendar belongs to a local account, so the calendar provider keeps
 * it on this phone and no sync adapter ever uploads it.
 */
class CalendarBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "vaulty/calendar"
        private const val REQUEST_CODE = 4127
        private const val ACCOUNT = "Vaulty"
        private const val DAY_MS = 24L * 60 * 60 * 1000
        private val PERMISSIONS = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val resolver get() = activity.contentResolver
    private var pendingAccess: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(granted())
            "requestAccess" -> requestAccess(result)
            "openSettings" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "home" -> result.success(mapOf("local" to true, "name" to "this phone"))
            "ensureCalendar" -> background(result) { ensureCalendar(call.argument<String>("id")?.toLongOrNull()) }
            "removeCalendar" -> background(result) { removeCalendar(call.argument<String>("id")?.toLongOrNull()) }
            "upsertEvent" -> background(result) { upsertEvent(call) }
            "deleteEvent" -> background(result) {
                call.argument<String>("id")?.toLongOrNull()?.let {
                    resolver.delete(ownUri(ContentUris.withAppendedId(Events.CONTENT_URI, it)), null, null)
                }
                null
            }
            "events" -> background(result) {
                events(call.argument<Number>("from")!!.toLong(), call.argument<Number>("to")!!.toLong())
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------- access --

    private fun granted() =
        PERMISSIONS.all { ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED }

    private fun requestAccess(result: MethodChannel.Result) {
        if (granted()) return result.success(true)
        if (pendingAccess != null) return result.error("BUSY", "Already asking for calendar access", null)
        pendingAccess = result
        ActivityCompat.requestPermissions(activity, PERMISSIONS, REQUEST_CODE)
    }

    /** Called from MainActivity. Returns whether the result was ours. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingAccess?.success(granted())
        pendingAccess = null
        return true
    }

    // ----------------------------------------------------------- calendar --

    /** As the local account's sync adapter, which owns its calendar outright. */
    private fun ownUri(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(Calendars.ACCOUNT_NAME, ACCOUNT)
        .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    private val ownSelection = "${Calendars.ACCOUNT_NAME} = ? AND ${Calendars.ACCOUNT_TYPE} = ?"
    private val ownArgs = arrayOf(ACCOUNT, CalendarContract.ACCOUNT_TYPE_LOCAL)

    private fun ownCalendarIds(): List<Long> =
        resolver.query(Calendars.CONTENT_URI, arrayOf(Calendars._ID), ownSelection, ownArgs, null)?.use { c ->
            buildList { while (c.moveToNext()) add(c.getLong(0)) }
        } ?: emptyList()

    /**
     * Returns the calendar to write to. `fresh` means it was just made, so it
     * holds none of the events Dart remembers. A leftover from before (an old
     * install, say) is replaced rather than reused, so nothing is duplicated.
     */
    private fun ensureCalendar(id: Long?): Map<String, Any> {
        val existing = ownCalendarIds()
        if (id != null && id in existing) return mapOf("id" to id.toString(), "fresh" to false)
        for (old in existing) resolver.delete(ownUri(ContentUris.withAppendedId(Calendars.CONTENT_URI, old)), null, null)
        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, ACCOUNT)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.OWNER_ACCOUNT, ACCOUNT)
            put(Calendars.NAME, "vaulty")
            put(Calendars.CALENDAR_DISPLAY_NAME, "Vaulty")
            put(Calendars.CALENDAR_COLOR, 0xFF5B44F2.toInt())
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.CALENDAR_TIME_ZONE, "UTC")
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
        }
        val uri = resolver.insert(ownUri(Calendars.CONTENT_URI), values)
            ?: throw IllegalStateException("Couldn't make the Vaulty calendar")
        return mapOf("id" to ContentUris.parseId(uri).toString(), "fresh" to true)
    }

    /** Deletes Vaulty's calendar; its events go with it. */
    private fun removeCalendar(id: Long?): Any? {
        for (own in ownCalendarIds()) {
            if (id == null || own == id) resolver.delete(ownUri(ContentUris.withAppendedId(Calendars.CONTENT_URI, own)), null, null)
        }
        return null
    }

    /** One all-day event, repeating if the item does. No alarms: Vaulty reminds. */
    private fun upsertEvent(call: MethodCall): String {
        val start = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(call.argument<Int>("year")!!, call.argument<Int>("month")!! - 1, call.argument<Int>("day")!!)
        }.timeInMillis
        val rule = when (call.argument<String>("recurrence")) {
            "YEARLY" -> "FREQ=YEARLY"
            "MONTHLY" -> "FREQ=MONTHLY"
            else -> null
        }
        val values = ContentValues().apply {
            put(Events.CALENDAR_ID, call.argument<String>("calendarId")!!.toLong())
            put(Events.TITLE, call.argument<String>("title"))
            put(Events.DESCRIPTION, call.argument<String>("notes"))
            put(Events.DTSTART, start)
            put(Events.ALL_DAY, 1)
            // All-day events must be in UTC, at midnight.
            put(Events.EVENT_TIMEZONE, "UTC")
            put(Events.HAS_ALARM, 0)
            put(Events.AVAILABILITY, Events.AVAILABILITY_FREE)
            // A repeating event has a duration instead of an end.
            if (rule == null) {
                put(Events.DTEND, start + DAY_MS)
                putNull(Events.RRULE)
                putNull(Events.DURATION)
            } else {
                put(Events.RRULE, rule)
                put(Events.DURATION, "P1D")
                putNull(Events.DTEND)
            }
        }
        call.argument<String>("eventId")?.toLongOrNull()?.let { id ->
            val updated = resolver.update(ownUri(ContentUris.withAppendedId(Events.CONTENT_URI, id)), values, null, null)
            if (updated > 0) return id.toString()
        }
        val uri = resolver.insert(ownUri(Events.CONTENT_URI), values)
            ?: throw IllegalStateException("Couldn't add the event")
        return ContentUris.parseId(uri).toString()
    }

    // ------------------------------------------------------------- import --

    /** Occurrences between [from] and [to] in other calendars, one per event. */
    private fun events(from: Long, to: Long): List<Map<String, String>> {
        val own = ownCalendarIds().toSet()
        val uri = Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        val projection = arrayOf(
            Instances.EVENT_ID,
            Instances.TITLE,
            Instances.BEGIN,
            Instances.ALL_DAY,
            Instances.CALENDAR_ID,
            Instances.CALENDAR_DISPLAY_NAME,
            Instances.RRULE,
            Instances.OWNER_ACCOUNT,
            Instances.CALENDAR_ACCESS_LEVEL,
        )
        // All-day events sit at UTC midnight; timed ones belong to the local day.
        fun format(zone: TimeZone) = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = zone }
        val utcDay = format(TimeZone.getTimeZone("UTC"))
        val localDay = format(TimeZone.getDefault())
        val seen = HashSet<Long>()
        val out = ArrayList<Map<String, String>>()
        resolver.query(uri, projection, null, null, "${Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) {
                val eventId = c.getLong(0)
                if (c.getLong(4) in own || !seen.add(eventId)) continue
                val allDay = c.getInt(3) == 1
                out.add(
                    mapOf(
                        "id" to eventId.toString(),
                        "title" to (c.getString(1) ?: ""),
                        "date" to (if (allDay) utcDay else localDay).format(c.getLong(2)),
                        "calendar" to (c.getString(5) ?: ""),
                        "kind" to kind(c.getString(7), c.getInt(8)),
                        "recurrence" to cadence(c.getString(6)),
                    ),
                )
            }
        }
        return out
    }

    /**
     * Contact birthdays, and read-only calendars someone else publishes (public
     * holidays, fixtures), which the import list doesn't tick up front.
     */
    private fun kind(owner: String?, access: Int): String = when {
        owner?.endsWith("#contacts@group.v.calendar.google.com") == true -> "birthdays"
        owner?.contains("#holiday@group.v.calendar.google.com") == true -> "subscribed"
        access <= Calendars.CAL_ACCESS_READ -> "subscribed"
        else -> "regular"
    }

    /** "FREQ=YEARLY" → "YEARLY". Anything fancier imports as a one-off. */
    private fun cadence(rrule: String?): String {
        if (rrule == null) return "NONE"
        val parts = rrule.uppercase(Locale.US).split(';').associate {
            it.substringBefore('=') to it.substringAfter('=', "")
        }
        if ((parts["INTERVAL"] ?: "1") != "1") return "NONE"
        return when (parts["FREQ"]) {
            "YEARLY" -> "YEARLY"
            "MONTHLY" -> "MONTHLY"
            else -> "NONE"
        }
    }

    // -------------------------------------------------------------- helpers --

    /** Calendar provider work is disk I/O, so it stays off the main thread. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("CALENDAR", e.message, null) }
            }
        }
    }
}
