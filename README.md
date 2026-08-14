# Rádio Santa Luzia

App iOS nativo em SwiftUI para a **Paróquia Santa Luzia**, integrado ao AzuraCast.

## Recursos

- Áudio Icecast com `AVPlayer`, reprodução em segundo plano e AirPlay
- metadados em tempo real via WebSocket/Centrifugo com reconexão exponencial
- progresso sincronizado, capa, título, artista, álbum, gênero, ISRC, letra e playlist
- próxima faixa, histórico, DJ ao vivo, ouvintes e status da estação
- seleção dos mounts/qualidades disponíveis
- pedidos musicais pela API pública do AzuraCast
- controles no Lock Screen, Control Center e acessórios Bluetooth
- Liquid Glass no iOS 26 e fallback nativo com Material no iOS 18+

## Estrutura

- `ios/`: app iOS nativo em SwiftUI, projeto Xcode e testes.
- `android/`: app Android nativo em Kotlin + Jetpack Compose, com a mesma identidade visual e recursos principais.

## Abrir

Abra `ios/RadioLuzia.xcodeproj` no Xcode, selecione sua equipe em **Signing & Capabilities** e execute em um iPhone ou simulador. O bundle id inicial é `br.com.cloudbrapp.radioluzia`.

Para Android, abra a pasta `android/` no Android Studio e sincronize o Gradle. O application id também é `br.com.cloudbrapp.radioluzia`.

O arquivo `ios/project.yml` documenta a estrutura do projeto iOS e pode ser usado com XcodeGen se desejado.
