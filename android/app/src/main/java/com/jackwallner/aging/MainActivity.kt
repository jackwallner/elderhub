package com.jackwallner.aging

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.lifecycleScope
import com.jackwallner.aging.data.InviteLink
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.RootScreen
import com.jackwallner.aging.ui.theme.AgingTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : ComponentActivity() {
    private val graph: AppGraph get() = (application as AgingApplication).graph

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = graph
        if (savedInstanceState == null) DebugLaunchOptions.apply(graph, intent)
        // Network-free: the cached session and circle, before first paint.
        graph.bootstrap()
        if (savedInstanceState == null) takeInvite(intent)
        enableEdgeToEdge()
        lifecycleScope.launch {
            graph.store.start()
            graph.auth.userId?.let { graph.store.identify(it.toString()) }
        }
        // Re-plan on every launch: a time-zone change or a missed boot broadcast must not leave reminders stale.
        graph.reminders.refresh()
        setContent {
            CompositionLocalProvider(LocalGraph provides graph) {
                AgingTheme {
                    // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) {
                        RootScreen(graph)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeInvite(intent)
    }

    /** An App Link to the join page, or the `elderhub://invite` fallback the page's button opens. */
    private fun takeInvite(intent: Intent?) {
        val uri = intent?.data ?: return
        InviteLink.code(uri)?.let { graph.pendingInviteCode = it }
    }

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly, like the iOS foreground refresh.
        lifecycleScope.launch { graph.store.refreshCustomerInfo() }
        // Every foreground: session, circle, membership and a sync, all after the UI is already up.
        lifecycleScope.launch { graph.refreshFromServer() }
    }
}
