package com.oryvex.oryvexcore

import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

data class StartRequest(
    val args: List<String>,
    val vpn: Boolean,
    val socksPort: Int,
    val fakeDns: Boolean,
    val ipv6: Boolean,
    val runId: Long,
) {
    fun toIntent(intent: Intent): Intent = intent
        .putStringArrayListExtra("args", ArrayList(args))
        .putExtra("vpn", vpn)
        .putExtra("socksPort", socksPort)
        .putExtra("fakeDns", fakeDns)
        .putExtra("ipv6", ipv6)
        .putExtra("runId", runId)

    fun save(ctx: Context) {
        val json = JSONObject()
            .put("args", JSONArray(args))
            .put("vpn", vpn)
            .put("socksPort", socksPort)
            .put("fakeDns", fakeDns)
            .put("ipv6", ipv6)
        ctx.getSharedPreferences("oryvexcore", Context.MODE_PRIVATE)
            .edit().putString("last", json.toString()).apply()
    }

    companion object {
        fun fromIntent(i: Intent): StartRequest? {
            val args = i.getStringArrayListExtra("args") ?: return null
            return StartRequest(
                args,
                i.getBooleanExtra("vpn", true),
                i.getIntExtra("socksPort", 1819),
                i.getBooleanExtra("fakeDns", true),
                i.getBooleanExtra("ipv6", true),
                i.getLongExtra("runId", System.currentTimeMillis()),
            )
        }

        /** The last request, for the system's always-on VPN, which starts us with no extras. */
        fun last(ctx: Context): StartRequest? = try {
            val raw = ctx.getSharedPreferences("oryvexcore", Context.MODE_PRIVATE)
                .getString("last", null) ?: return null
            val j = JSONObject(raw)
            val a = j.getJSONArray("args")
            StartRequest(
                (0 until a.length()).map { a.getString(it) },
                j.optBoolean("vpn", true),
                j.optInt("socksPort", 1819),
                j.optBoolean("fakeDns", true),
                j.optBoolean("ipv6", true),
                System.currentTimeMillis(),
            )
        } catch (_: Throwable) {
            null
        }
    }
}
