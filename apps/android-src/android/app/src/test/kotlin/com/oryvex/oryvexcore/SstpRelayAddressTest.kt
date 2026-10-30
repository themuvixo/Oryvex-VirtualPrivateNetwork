package com.oryvex.oryvexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SstpRelayAddressTest {
    @Test fun preservesVpnGateDnsHostnameAndDefaultPort() {
        assertEquals("public-vpn-12.opengw.net" to 443, SstpRelayAddress.parse("public-vpn-12.opengw.net"))
    }

    @Test fun preservesNonDefaultPort() {
        assertEquals("vpn123.opengw.net" to 1443, SstpRelayAddress.parse("vpn123.opengw.net:1443"))
    }

    @Test fun rejectsIpAddressUrlAndOutOfRangePort() {
        assertNull(SstpRelayAddress.parse("219.100.37.1"))
        assertNull(SstpRelayAddress.parse("https://vpn123.opengw.net"))
        assertNull(SstpRelayAddress.parse("vpn123.opengw.net:70000"))
    }
}
