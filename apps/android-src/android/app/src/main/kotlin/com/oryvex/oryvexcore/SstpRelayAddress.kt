package com.oryvex.oryvexcore

/** Validates VPN Gate's TLS hostname form and optional TCP port without ever using the listed IP. */
internal object SstpRelayAddress {
    private val pattern = Regex(
        "(?i)^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\\.opengw\\.net)(?::([0-9]{1,5}))?$"
    )

    fun parse(value: String): Pair<String, Int>? {
        val match = pattern.matchEntire(value.trim()) ?: return null
        val port = match.groupValues[2].takeIf { it.isNotEmpty() }?.toIntOrNull() ?: 443
        if (port !in 1..65535) return null
        return match.groupValues[1].lowercase() to port
    }
}
