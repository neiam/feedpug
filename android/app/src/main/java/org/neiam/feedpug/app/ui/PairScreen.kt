package org.neiam.feedpug.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.journeyapps.barcodescanner.CaptureActivity
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.launch
import org.neiam.feedpug.app.data.FeedPugClient
import org.neiam.feedpug.app.data.PairPayload
import org.neiam.feedpug.app.data.TokenStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PairScreen(
    prefilled: PairPayload?,
    tokens: TokenStore,
    onPaired: () -> Unit,
) {
    var baseUrl by remember { mutableStateOf(prefilled?.baseUrl ?: "") }
    var token by remember { mutableStateOf(prefilled?.token ?: "") }
    var status by remember { mutableStateOf<PairStatus>(PairStatus.Idle) }
    val scope = rememberCoroutineScope()

    val scanLauncher = rememberLauncherForActivityResult(ScanContract()) { result ->
        val raw = result.contents ?: return@rememberLauncherForActivityResult
        val parsed = PairPayload.parse(raw)
        if (parsed != null) {
            baseUrl = parsed.baseUrl
            token = parsed.token
            status = PairStatus.Idle
        } else {
            status = PairStatus.Error("That QR didn't look like a FeedPug pair code.")
        }
    }

    Scaffold(topBar = { TopAppBar(title = { Text("Pair with FeedPug") }) }) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "On the web app, open the account menu → Devices, generate a token, " +
                    "then scan its QR. You can also paste the URI or fields directly.",
                style = MaterialTheme.typography.bodyMedium,
            )

            Button(
                onClick = {
                    scanLauncher.launch(ScanOptions().apply {
                        setPrompt("Point at the FeedPug pairing QR")
                        setBeepEnabled(false)
                        setOrientationLocked(false)
                        captureActivity = CaptureActivity::class.java
                    })
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Scan QR")
            }

            OutlinedTextField(
                value = baseUrl,
                onValueChange = { baseUrl = it },
                label = { Text("Server URL") },
                placeholder = { Text("https://feedpug.example.com") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            OutlinedTextField(
                value = token,
                onValueChange = { token = it },
                label = { Text("API token") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Button(
                enabled = baseUrl.isNotBlank() && token.isNotBlank() && status !is PairStatus.Verifying,
                onClick = {
                    val creds = TokenStore.Credentials(baseUrl.trim().trimEnd('/'), token.trim())
                    status = PairStatus.Verifying
                    scope.launch {
                        status = try {
                            val profile = FeedPugClient.build(creds).profile()
                            tokens.save(creds.baseUrl, creds.token)
                            PairStatus.Success(profile.user.email)
                        } catch (e: Exception) {
                            PairStatus.Error("Couldn't reach the server: ${e.message}")
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (status is PairStatus.Verifying) "Verifying…" else "Connect")
            }

            when (val s = status) {
                is PairStatus.Idle, PairStatus.Verifying -> {}
                is PairStatus.Success -> {
                    Text("Connected as ${s.email}", color = MaterialTheme.colorScheme.primary)
                    Button(onClick = onPaired, modifier = Modifier.fillMaxWidth()) { Text("Continue") }
                }
                is PairStatus.Error -> Text(s.message, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private sealed interface PairStatus {
    data object Idle : PairStatus
    data object Verifying : PairStatus
    data class Success(val email: String) : PairStatus
    data class Error(val message: String) : PairStatus
}
