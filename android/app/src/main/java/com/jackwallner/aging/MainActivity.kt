package com.jackwallner.aging

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
        enableEdgeToEdge()
        lifecycleScope.launch { graph.store.start() }
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

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly, like the iOS foreground refresh.
        lifecycleScope.launch { graph.store.refreshCustomerInfo() }
    }
}
