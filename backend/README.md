# Backend da Rádio Santa Luzia

API Node.js/Express, banco libSQL remoto (Turso) ou SQLite local e painel responsivo em português, servido pelo mesmo processo. Não exige conta dos ouvintes. O único login é o administrativo. O painel usa HTML/CSS/JavaScript sem etapa de build, mantendo a instalação do backend simples.

## Executar

Requer Node.js 22. Na Vercel, a versão está definida em `package.json`.

```sh
cd backend
npm ci
cp .env.example .env
# Edite .env e defina uma ADMIN_PASSWORD única, com ao menos 10 caracteres.
npm start
```

Abra http://127.0.0.1:3000. A senha não é incluída nos aplicativos. `.env`, banco e dependências são ignorados pelo Git. Para desenvolvimento com reinício automático: `npm run dev`. Verificação: `npm test`.

## Uso com AzuraCast

1. Em **Conteúdos**, informe título, tipo e URL HTTPS.
2. Para uma **Transmissão**, copie o endereço direto do mount na área de transmissões do AzuraCast (ex.: `https://servidor/listen/estacao/radio.mp3`). Uma transmissão pode conter apenas gravações, conforme a programação feita no AzuraCast.
3. Para **Áudio gravado**, use uma URL HTTPS que responda com o arquivo de áudio (MP3, AAC ou outro formato suportado pelos dois sistemas). Esses itens aparecem também no catálogo dos apps, como um programa com um episódio.
4. Para **Página pública**, use a URL pública do player ou da página de podcasts; ela abre externamente, nos detalhes da rádio.
5. Para **Podcast (feed RSS)**, copie o link RSS do podcast. O feed é publicado como link externo nos detalhes. Esta versão não importa nem interpreta episódios de feeds RSS. Para reprodução nativa, cadastre cada áudio de episódio como **Áudio gravado**.
6. Confirme os direitos, marque **Publicar no app** e, para áudio/transmissão, **Usar como reprodução principal**. Apenas um item pode ser principal. Os demais áudios gravados publicados ficam no catálogo de programas do app. Outras transmissões ficam cadastradas e podem ser escolhidas como principal no painel.
7. Rascunhos ficam apenas no painel. Excluir/despublicar o principal deixa o endpoint de reprodução indisponível até você definir outro principal. Não há retorno automático à transmissão antiga.

As URLs são validadas quanto ao formato HTTPS, mas o backend não baixa nem analisa o arquivo. Confirme a acessibilidade e o formato real do áudio nos dispositivos. Não coloque tokens privados ou senhas nas URLs: links publicados são públicos.

O campo **Programação exclusiva de conteúdo gravado** registra sua declaração editorial; não filtra, fiscaliza nem modifica o áudio do AzuraCast. Nome, endereço AzuraCast e ID são disponibilizados na configuração pública para integrações. Os players gerenciados reproduzem os links cadastrados diretamente, sem consultar a API original para metadados. Não há consulta de ouvintes, teste de sinal, arte ou duração: `is_online` significa que existe principal publicado, e as contagens/durações do contrato de compatibilidade são zero.

## Conectar iOS e Android

O backend precisa estar hospedado com HTTPS válido. Como ainda não há domínio definido, os apps preservam a integração anterior enquanto o endereço abaixo estiver vazio. **Defina o endereço nos dois apps antes de distribuir a versão gerenciada**; deixar vazio continua usando a rádio original, inclusive suas configurações de pedidos musicais.

- **iOS:** em `ios/RadioLuzia/Resources/Info.plist`, preencha `RadioBackendURL` com a URL base, por exemplo `https://api.sua-radio.com` (sem `/api/v1`). Compile novamente no Xcode. No modo gerenciado, o WebSocket original não é conectado; a configuração de reprodução é consultada a cada 15 segundos.
- **Android:** em `android/gradle.properties`, adicione `RADIO_BACKEND_URL=https://api.sua-radio.com`, ou forneça `-PRADIO_BACKEND_URL=https://api.sua-radio.com` ao Gradle. Compile uma nova versão. O app consulta os dados a cada 15 segundos.

Depois dessa primeira compilação, novas URLs não exigem atualização na loja. As consultas atualizam o áudio principal disponível; um áudio já em execução não é trocado automaticamente no meio da reprodução. Os catálogos de áudios são atualizados ao abrir a seção. Com o backend configurado, falhas não redirecionam para a rádio antiga. Os pedidos musicais ficam desativados. Páginas e RSS aparecem em **Sobre a transmissão**.

## API

Sem autenticação, somente conteúdo publicado:

| Método | Endpoint | Retorno |
| --- | --- | --- |
| GET | `/health` | Saúde do processo |
| GET | `/api/v1/config` | Configuração, principal e conteúdos publicados |
| GET | `/api/v1/nowplaying` | Contrato compatível com os players existentes; 503 sem principal |
| GET | `/api/v1/podcasts` | Catálogo de áudios gravados publicados |
| GET | `/api/v1/podcast/:id/episodes` | Link de reprodução do áudio |

Administração:

| Método | Endpoint | Uso |
| --- | --- | --- |
| POST | `/api/admin/login` | JSON `{ "password": "..." }`; define cookie HttpOnly e retorna `csrf` |
| GET | `/api/admin/session` | Recupera token CSRF da sessão |
| POST | `/api/admin/logout` | Encerra sessão |
| GET / POST | `/api/admin/contents` | Lista / cria |
| PUT / DELETE | `/api/admin/contents/:id` | Substitui / exclui |
| GET / PUT | `/api/admin/settings` | Lê / substitui configurações |

Escritas autenticadas exigem cookie e cabeçalho `X-CSRF-Token`. Sessões expiram em oito horas. Há limites de requisições e de tentativas de login.

Exemplo de conteúdo:

```json
{
  "title": "Reflexão da semana",
  "type": "audio",
  "url": "https://seu-servidor.com/reflexao.mp3",
  "description": "Reflexão produzida pela paróquia.",
  "published": true,
  "primary": true,
  "rightsConfirmed": true
}
```

Tipos: `stream`, `audio`, `public_page`, `podcast_feed`. A confirmação de direitos é uma declaração administrativa; não é análise jurídica, certificado nem autorização emitida pelo backend.

## Publicar na Vercel

A configuração segue o [suporte oficial de Express na Vercel](https://vercel.com/docs/frameworks/backend/express): `app.js` exporta o handler sem abrir uma porta, e os arquivos em `public/` são servidos pela CDN. `vercel.json` seleciona Express e configura os cabeçalhos de segurança também para o painel estático.

1. Crie um banco **libSQL** no [Turso](https://docs.turso.tech/sdk/ts/reference#libsqlclient). Copie a URL de conexão (`libsql://...`) e gere um token de acesso ao banco. Esta integração usa `@libsql/client`; selecione um banco compatível com libSQL.
2. Importe este repositório em um novo projeto da Vercel e defina **Root Directory = `backend`**.
3. Use **Framework Preset = Express**, **Node.js = 22.x** e **Install Command = `npm ci`**. Deixe **Build Command** e **Output Directory** sem sobrescrita; o projeto não precisa de build frontend. O `vercel.json` já informa o framework.
4. Em **Settings → Environment Variables**, configure:

   | Variável | Valor |
   | --- | --- |
   | `ADMIN_PASSWORD` | Senha administrativa única, com pelo menos 10 caracteres |
   | `TURSO_DATABASE_URL` | URL `libsql://...` ou HTTPS do banco remoto |
   | `TURSO_AUTH_TOKEN` | Token de acesso ao banco |

   Cadastre as variáveis em **Production**. Para previews, use um banco e credenciais separados para evitar que alterações de teste afetem a rádio em produção. Nunca adicione os segredos ao código ou aos aplicativos móveis.
5. Faça o deploy. As tabelas são criadas automaticamente no primeiro acesso. O cadastro inicial fica vazio; o banco remoto não importa automaticamente dados de um SQLite local existente.
6. Abra `https://seu-projeto.vercel.app`, entre com a senha e cadastre o áudio principal. Confira `/health` e `/api/v1/config`.
7. Configure `https://seu-projeto.vercel.app` em `RadioBackendURL` no iOS e `RADIO_BACKEND_URL` no Android. Se o domínio estiver protegido pelo recurso Deployment Protection, libere o acesso público da produção para que os apps possam consultar a API sem login da Vercel.

Também é possível usar a [CLI oficial da Vercel](https://vercel.com/docs/frameworks/backend/express#deploying-the-application) a partir da pasta `backend`, depois de configurar o projeto e suas variáveis. O projeto não inclui credenciais de conta nem realiza publicação automaticamente.

Na Vercel, **não use `DATABASE_PATH` nem arquivos em `/tmp` como banco persistente**. A aplicação recusa inicialização nesse ambiente se não houver banco remoto e token configurados. Conteúdos, sessões e contadores de limite de requisições ficam no mesmo banco remoto, compartilhados entre instâncias. A seleção do principal usa transação para evitar dois principais publicados. Os apps continuam reproduzindo o áudio diretamente do AzuraCast; a Vercel serve o painel e a configuração, sem retransmitir os arquivos de áudio.

`TURSO_DATABASE_URL` e `TURSO_AUTH_TOKEN` também podem ser usados localmente. Como alternativa, são aceitos os nomes `DATABASE_URL` e `DATABASE_AUTH_TOKEN`. Se as variáveis de banco remoto estiverem vazias fora da Vercel, o desenvolvimento usa `DATABASE_PATH=./data/radio.sqlite`, compatível com o banco criado pela versão anterior.

## Resolver falhas de publicação

- **GitHub Pages / Jekyll informa `/github/workspace/docs` inexistente:** o repositório está com Pages configurado para uma pasta ausente. Essa execução é independente da Vercel. Se a hospedagem usada será apenas a Vercel, em GitHub → Settings → Pages → Build and deployment → Branch, selecione **None** e salve. O código deste backend não precisa de GitHub Pages.
- **Vercel retorna 503:** confira `ADMIN_PASSWORD`, `TURSO_DATABASE_URL` e `TURSO_AUTH_TOKEN` nas variáveis de **Production** e faça **Redeploy**. Preencher `.env.example` no GitHub não configura a Vercel. A resposta inclui `BACKEND_CONFIGURATION_INVALID` para variáveis ausentes/inválidas e `BACKEND_DATABASE_UNAVAILABLE` para erros de conexão/inicialização. Consulte também os Runtime Logs, que registram códigos sem expor os valores das credenciais.
- O painel estático abre mesmo quando a API não consegue inicializar; o login informa o diagnóstico. `/health` continua retornando 503 enquanto o backend não estiver funcional.
- Se um token ou senha real tiver sido commitado, substitua-o no serviço e configure o novo valor na Vercel. Limpar o arquivo atual não remove os valores de commits antigos. `.env` é local e ignorado pelo Git; `.env.example` deve conter apenas campos vazios ou exemplos sem credenciais.

## Outras hospedagens Node

Para servidor próprio, execute Node atrás de um proxy reverso com TLS. Use `NODE_ENV=production` para cookies Secure. Configure `PORT`, `HOST` e, se usar SQLite local, `DATABASE_PATH` em volume persistente. Para proxy reverso local, use `TRUST_PROXY=loopback`; com proxy em outra máquina, informe apenas os IPs/sub-redes confiáveis. Na Vercel, o proxy e os cookies Secure são configurados automaticamente.

Faça backups do banco. Mudanças de variáveis na Vercel exigem novo deploy; em servidor próprio, reinicie o processo. Sessões existentes expiram em oito horas; para revogar todas imediatamente, limpe a tabela `sessions` do banco.

Nenhuma hospedagem, banco remoto, credencial de produção ou publicação nas lojas foi criada por esta implementação.

## Apple e direitos de conteúdo

Se por “CAD” você quis dizer **ECAD**, este projeto não determina se uma licença é exigida no seu caso. Conteúdo gravado pode incluir obras de terceiros, trilhas, vinhetas ou outros materiais protegidos. Use conteúdo próprio ou autorizado e guarde os comprovantes; a configuração não dispensa obrigações aplicáveis.

As [diretrizes oficiais da Apple](https://developer.apple.com/app-store/review/guidelines/) exigem direitos sobre o conteúdo (5.2), permitem solicitar comprovação e também avaliam funcionalidade mínima (4.2). Um player com conteúdo original pode ser submetido, mas a aprovação é decidida pela Apple. Não use mudanças remotas para ocultar conteúdo na revisão ou oferecer conteúdo não autorizado depois dela.

Nas notas de revisão, descreva corretamente a produção e titularidade do conteúdo, a hospedagem no AzuraCast, a reprodução nativa e os links externos. Forneça autorizações quando aplicáveis. Se houver uma rejeição, use o texto exato da Apple para identificar a exigência; não presuma que ela desapareça ao trocar o formato por podcast.
