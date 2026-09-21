# Configuração KeyAuth — 3105

O app usa exclusivamente a API KeyAuth. No painel KeyAuth, crie as keys e escolha a duração desejada. O usuário digita a key na IPA; a aplicação envia a licença para `https://keyauth.win/api/1.3/`, vinculando-a ao identificador da instalação.

O app revalida a licença antes de liberar a área principal, ao retornar ao primeiro plano e durante a entrada pelo obturador. Se a key for apagada, expirar ou for banida, a sessão local é removida e o usuário volta para a tela de ativação.

O owner secret não está embutido na IPA. As configurações públicas do aplicativo são necessárias para a API KeyAuth; a segurança da licença depende da validação no servidor KeyAuth.
