# Rádio Santa Luzia

Aplicativos nativos iOS (SwiftUI) e Android (Kotlin/Compose) para a **Paróquia Santa Luzia**, com reprodução controlada pela API administrativa.

## Recursos

- Reprodução do conteúdo principal publicado em `https://radio-luzia.vercel.app`
- Transmissões e áudios gravados hospedados no AzuraCast ou em outro servidor HTTPS
- Catálogo nativo de podcasts com episódios de feeds RSS/Atom publicados no painel
- Atualização da configuração a cada 15 segundos e revalidação ao iniciar/retomar
- Troca do áudio em execução quando seu endereço é alterado na API
- Interrupção de conteúdos removidos/despublicados ou cuja publicação não possa ser verificada
- Reprodução em segundo plano, AirPlay no iOS e controles de mídia/Bluetooth
- Páginas públicas acessíveis como links, sem tratá-las como arquivos de áudio
- Liquid Glass no iOS 26 e Material no iOS 18+

A API é a única fonte de reprodução. Os apps não retomam a transmissão antiga em caso de falha e não disponibilizam pedidos musicais.

## Estrutura

- `ios/`: app iOS nativo em SwiftUI, projeto Xcode e testes.
- `android/`: app Android nativo em Kotlin + Jetpack Compose, com a mesma identidade visual e recursos principais.

## Abrir

Abra `ios/RadioLuzia.xcodeproj` no Xcode, selecione sua equipe em **Signing & Capabilities** e execute em um iPhone ou simulador. O bundle id inicial é `br.com.cloudbrapp.radioluzia`.

Para Android, abra a pasta `android/` no Android Studio e sincronize o Gradle. O application id é `org.santaluzia.radio`.

O arquivo `ios/project.yml` documenta a estrutura do projeto iOS e pode ser usado com XcodeGen se desejado.

## Painel e API de conteúdos

A pasta [`backend/`](backend/README.md) contém o painel administrativo com login, banco libSQL/Turso (ou SQLite local) e API pública para definir links de transmissão, áudios gravados, páginas públicas e feeds de podcast. Consulte o guia para executar, hospedar e configurar o endereço do backend nos aplicativos iOS/Android.

O backend está preparado para a Vercel com `backend` como Root Directory. O guia inclui as variáveis do banco remoto e a configuração do deploy.
