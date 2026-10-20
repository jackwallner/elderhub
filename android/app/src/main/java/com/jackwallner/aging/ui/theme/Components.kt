package com.jackwallner.aging.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Large left-aligned title, the iOS large navigation title. */
@Composable
fun ScreenTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold, fontSize = 32.sp),
        color = AgingTheme.colors.text,
        modifier = modifier.padding(horizontal = Spacing.lg).padding(top = Spacing.lg, bottom = Spacing.sm).semantics { heading() },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailTopBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit = {}) {
    CenterAlignedTopAppBar(
        title = { Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)) },
        navigationIcon = {
            IconButton(onClick = onBack, modifier = Modifier.testTag("nav.back")) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
        },
        actions = actions,
        // The root Scaffold already pads for the status bar.
        windowInsets = WindowInsets(0),
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AgingTheme.colors.background),
    )
}

/** Small caps-free section header above a card, like an iOS inset-grouped section. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
        color = AgingTheme.colors.secondaryText,
        modifier = modifier.padding(start = Spacing.lg + 4.dp, end = Spacing.lg, top = Spacing.lg, bottom = 6.dp).semantics { heading() },
    )
}

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .padding(horizontal = Spacing.lg)
            .fillMaxWidth()
            .clip(RoundedCornerShape(Spacing.cardRadius))
            .background(AgingTheme.colors.card),
        content = content,
    )
}

@Composable
fun RowDivider() {
    HorizontalDivider(color = AgingTheme.colors.separator, thickness = 0.5.dp, modifier = Modifier.padding(start = Spacing.lg))
}

/** One tappable list row: title, optional detail, optional leading icon, chevron. */
@Composable
fun NavRow(
    title: String,
    detail: String? = null,
    icon: ImageVector? = null,
    tint: Color = AgingTheme.colors.accent,
    trailing: String? = null,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)?,
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = Spacing.lg, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            IconBadge(icon, tint)
            Spacer(Modifier.width(Spacing.md))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.text)
            if (!detail.isNullOrEmpty()) {
                Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
            }
        }
        if (trailing != null) {
            Text(trailing, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
        }
        if (onClick != null) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = AgingTheme.colors.secondaryText.copy(alpha = 0.6f))
        }
    }
}

@Composable
fun IconBadge(icon: ImageVector, tint: Color, size: Int = 32) {
    Box(
        Modifier.size(size.dp).clip(RoundedCornerShape(8.dp)).background(tint.copy(alpha = 0.14f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size((size * 0.58).dp))
    }
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = AgingTheme.colors.accent, contentColor = AgingTheme.colors.onAccent),
        modifier = modifier.fillMaxWidth().heightIn(min = 52.dp),
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold))
    }
}

/** The person's initial in a tinted circle, like the iOS avatar. */
@Composable
fun Avatar(name: String, index: Int, size: Int = 44) {
    val tints = listOf(Color(0xFF3378D9), Color(0xFFE0703D), Color(0xFF2E9E7A), Color(0xFF8A5CD6), Color(0xFFCC4F7A))
    val tint = tints[Math.floorMod(index, tints.size)]
    Box(Modifier.size(size.dp).clip(CircleShape).background(tint.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Text(
            name.trim().firstOrNull()?.uppercase() ?: "?",
            color = tint,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, fontSize = (size * 0.42).sp),
        )
    }
}

/** A header stat: big number, small caption. */
@Composable
fun StatTile(value: String, caption: String, modifier: Modifier = Modifier, tint: Color = AgingTheme.colors.text) {
    Column(
        modifier.clip(RoundedCornerShape(12.dp)).background(AgingTheme.colors.fill).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = tint)
        Text(caption, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText, maxLines = 1)
    }
}

/** A hub tile that says what a feature is for (`FeatureTile` on iOS). */
@Composable
fun FeatureTile(
    title: String,
    blurb: String,
    icon: ImageVector,
    tint: Color,
    status: String?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier
            .clip(RoundedCornerShape(Spacing.cardRadius))
            .background(AgingTheme.colors.card)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        IconBadge(icon, tint, size = 34)
        Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
        Text(blurb, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText, minLines = 2, maxLines = 3)
        if (status != null) {
            Text(status, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = tint, maxLines = 2)
        }
    }
}

@Composable
fun EmptyNote(title: String, detail: String) {
    Column(Modifier.fillMaxWidth().padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), color = AgingTheme.colors.text)
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
    }
}
