from pathlib import Path

main = Path(
    'android/app/src/main/kotlin/'
    'com/dreampulse/assistant/MainActivity.kt'
)
text = main.read_text()

needle = '''                "speak" -> {'''
diag = '''                "diagnose" -> {
                    val receiver =
                        object : ResultReceiver(
                            Handler(Looper.getMainLooper())
                        ) {
                            override fun onReceiveResult(
                                resultCode: Int,
                                resultData: Bundle?,
                            ) {
                                val stage =
                                    resultData?.getString("stage")
                                        ?: "unknown"

                                if (
                                    resultCode ==
                                    DreamPulseVoiceService.RESULT_OK
                                ) {
                                    result.success(
                                        mapOf(
                                            "message" to (
                                                resultData?.getString(
                                                    "message"
                                                ) ?: "DIAG OK"
                                            ),
                                            "stage" to stage,
                                        )
                                    )
                                } else {
                                    result.error(
                                        "VOICE_DIAG",
                                        (
                                            resultData?.getString(
                                                "error"
                                            )
                                                ?: "Voice diagnostic failed"
                                        ) + " · этап: " + stage,
                                        null,
                                    )
                                }
                            }
                        }

                    val intent =
                        Intent(
                            this,
                            DreamPulseVoiceService::class.java,
                        ).apply {
                            action =
                                DreamPulseVoiceService
                                    .ACTION_DIAGNOSE
                            putExtra(
                                DreamPulseVoiceService
                                    .EXTRA_RECEIVER,
                                receiver,
                            )
                        }

                    try {
                        startService(intent)
                    } catch (e: Throwable) {
                        result.error(
                            "VOICE_DIAG_START",
                            e.message ?: e.javaClass.simpleName,
                            null,
                        )
                    }
                }

'''

if needle not in text:
    raise SystemExit('MainActivity speak marker not found')

text = text.replace(needle, diag + needle, 1)
main.write_text(text)
