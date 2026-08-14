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

## Abrir

Abra `RadioLuzia.xcodeproj` no Xcode, selecione sua equipe em **Signing & Capabilities** e execute em um iPhone ou simulador. O bundle id inicial é `br.com.cloudbrapp.radioluzia`.

O arquivo `project.yml` documenta a estrutura e pode ser usado com XcodeGen se desejado.
