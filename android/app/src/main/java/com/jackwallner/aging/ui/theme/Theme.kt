package com.jackwallner.aging.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Tokens from the iOS app: the `AccentColor` asset (light and dark), the
 * grouped-list backgrounds, and the hub tints in `HubComponents.swift`.
 */
@Immutable
data class AgingColors(
    val accent: Color,
    val background: Color,
    val card: Color,
    val text: Color,
    val secondaryText: Color,
    val separator: Color,
    val fill: Color,
    val taken: Color,
    val warning: Color,
    val danger: Color,
    val onAccent: Color = Color.White,
)

val LightColors = AgingColors(
    accent = Color(0xFF3378D9),
    background = Color(0xFFF2F2F7),
    card = Color.White,
    text = Color(0xFF111114),
    secondaryText = Color(0xFF6B6B73),
    separator = Color(0xFFE2E2E7),
    fill = Color(0xFFEDEDF2),
    taken = Color(0xFF1E8E4E),
    warning = Color(0xFFC46A00),
    danger = Color(0xFFCC4047),
)

val DarkColors = AgingColors(
    accent = Color(0xFF5A9DEE),
    background = Color(0xFF000000),
    card = Color(0xFF1C1C1E),
    text = Color(0xFFF2F2F5),
    secondaryText = Color(0xFFA0A0A8),
    separator = Color(0xFF38383C),
    fill = Color(0xFF2C2C2E),
    taken = Color(0xFF34C468),
    warning = Color(0xFFFF9F0A),
    danger = Color(0xFFFF5A5F),
)

object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
    val cardRadius = 14.dp
    val touch = 48.dp
}

val LocalAgingColors = staticCompositionLocalOf { LightColors }

object AgingTheme {
    val colors: AgingColors @Composable get() = LocalAgingColors.current
}

@Composable
fun AgingTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) DarkColors else LightColors
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent, background = colors.background,
            surface = colors.card, onSurface = colors.text, onBackground = colors.text,
            surfaceVariant = colors.fill, onSurfaceVariant = colors.secondaryText, outlineVariant = colors.separator,
            surfaceContainer = colors.card, surfaceContainerHigh = colors.card, surfaceContainerHighest = colors.fill,
            error = colors.danger,
        )
    } else {
        lightColorScheme(
            primary = colors.accent, onPrimary = colors.onAccent, background = colors.background,
            surface = colors.card, onSurface = colors.text, onBackground = colors.text,
            surfaceVariant = colors.fill, onSurfaceVariant = colors.secondaryText, outlineVariant = colors.separator,
            surfaceContainer = colors.card, surfaceContainerHigh = colors.card, surfaceContainerHighest = colors.fill,
            error = colors.danger,
        )
    }
    CompositionLocalProvider(LocalAgingColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
