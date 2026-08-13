---
title: "【勉強】Okta Customer Identity Cloud (Auth0) — ユーザー／グループ管理（2026-08-13）"
date: 2026-08-13
product: Okta Customer Identity Cloud (Auth0)
notion_url: https://app.notion.com/p/3ba3617f2dbe812c9fa2d08f734ec851
---

# 【勉強】Okta Customer Identity Cloud (Auth0) — ユーザー／グループ管理（2026-08-13）

## 今日のテーマ

Auth0 でユーザーをどう管理し、どうまとめるかを押さえます。8/10 の Entra ID 編、8/11 の Okta Workforce 編、8/12 の Ping Identity 編と同じテーマですが、**Auth0 の標準機能には「グループ」という箱がありません**（レガシーの Authorization Extension は例外。後述）。代わりに **Role（ロール）** と **Organization（組織）** という2つの仕組みで人をまとめます。ここが今日の山場です。

## 概要 — 「グループがない」という前提から始める

Entra ID にはグループ、Okta にもグループ、Ping には Population とグループがありました。Auth0 のダッシュボードには User Management > Users と User Management > Roles が並んでいますが、**Groups というメニューはありません**。

これは Auth0 が CIAM（顧客向け ID 管理）製品として設計されているからです。社員をディレクトリで組織図的に整理する必要がなく、代わりに「このユーザーは何ができるか（Role）」と「このユーザーはどの取引先企業の人か（Organization）」を管理したい、という発想になっています。

なお、レガシー機能の **Authorization Extension** には Groups があります。ただし現行の Authorization Core（標準の User Management > Roles）とは別系統の機能で、公式も「Authorization Core は Extension のような groups をサポートしない」と明記しています。新規設計で Extension を選ぶ理由はほぼないので、本記事では「標準機能にグループはない」という前提で進めます。

まず全体像を整理します。

```mermaid
graph TD
  Tenant["Tenant（テナント）"]
  Tenant --> Conn["Connection（接続）<br>ユーザーの出どころ"]
  Conn --> DB["Database Connection<br>Auth0内蔵DB／自前DB"]
  Conn --> Soc["Social Connection<br>Google, GitHub など"]
  Conn --> Ent["Enterprise Connection<br>SAML, OIDC など"]
  Tenant --> User["User（ユーザー）<br>root属性＋user_metadata＋app_metadata"]
  Tenant --> Role["Role（ロール）<br>Permissionの束"]
  Role --> Perm["Permission（権限）<br>API単位で定義"]
  Tenant --> Org["Organization（組織）"]
  Org --> Member["Member（メンバー）＝ユーザー"]
  Org --> OrgRole["組織スコープのロール"]
  Conn -.->|"ここに所属する"| User
  Role -.->|"割り当て"| User
  Member -.-> User
```

上図はテナント配下の主な登場人物です。ユーザーは必ずどこかの Connection に属し、Role と Organization は横から重ねる形で紐づきます。

## 押さえる要点

### 1. ユーザーは「Connection」に属する

Auth0 の Connection とは「**Auth0 とユーザーのソース（供給元）との関係**」です。公式は "A connection is the relationship between Auth0 and a source of users" と定義しています。ソースには外部 IdP（Google など）、データベース、パスワードレス方式などがあります。

Database Connection の場合、資格情報の置き場所は2択です。

- **Auth0 のユーザーストア** — Auth0 が DB 基盤を提供する既定の方式。すべてのデータが Auth0 側にあるため認証処理の性能が最も良い、と公式は説明しています。
- **カスタムデータベース** — 既存のユーザーストアを使う方式。ログイン用スクリプトを自分で書き、サインアップ・メール検証・パスワードリセット・ユーザー削除のスクリプトを任意で追加します。

ここでインフラ出身者がつまずきやすい点。**複数のカスタム DB Connection を使う場合、返す `id`（= `user_id`）は全 Connection をまたいで一意にする必要があります。** 公式は「ID の衝突を避けるため `id` の値に Connection 名を接頭辞として付けることを推奨」しています。LDAP の DN のような一意性を、自分で担保しに行く感覚です。

### 2. ユーザープロファイルは「root属性」＋「2種類のメタデータ」

Auth0 のユーザープロファイルには、追加情報を入れるための副格納領域が2つあります。**この2つの使い分けが実務でいちばん効きます。**

| | user_metadata | app_metadata |
|---|---|---|
| 入れるもの | 好みや設定など、**中核機能に影響しない**属性 | サポートプラン、セキュリティロール、アクセス制御グループなど、**中核機能に影響する**情報 |
| 本人が編集できるか | **できる**（`update:current_user_metadata` 等のスコープを持つトークンで、本人が Management API から変更可） | **できない** |
| 典型的な用途 | 言語設定、テーマ、通知の可否 | ユーザーの状態、内部フラグ |

メタデータは root 属性とマージされず、`app_metadata` / `user_metadata` という別セクションに格納されます。ダッシュボード、Management API、Actions から読み書きできます。

**「アクセス制御グループを app_metadata に入れる」** という公式の例示は重要です。標準機能に group エンティティがないので、独自の組織分類が欲しければ app_metadata に自分で持つ、というのが素直な実装になります。

### 3. Role と Permission — RBAC は「API 単位」で有効化する

- **Permission（権限）** — API（Resource Server）に対して定義する操作単位。
- **Role（ロール）** — 「**ユーザーに適用できる Permission の集まり**」。公式は個別にパーミッションを付けるよりロール経由のほうが追加・削除・調整が楽になると説明しています。

設定の流れはこうです。

1. **Dashboard > Applications > APIs** で対象 API を開き、**RBAC Settings** の **Enable RBAC** をオンにする。
2. アクセストークンの `permissions` クレームにユーザーの全パーミッションを載せたい場合は、**Add Permissions in the Access Token** もオンにする。
3. **Dashboard > User Management > Roles** でロールを開き、**Permissions** タブから **Add Permissions** で権限を束ねる。
4. ユーザーにロールを割り当てる。ログイン時の認可フローで Auth0 がロールと権限を評価します。

Management API 経由でも同じことができます。ロール割り当ての例:

```bash
curl -X POST 'https://YOUR_DOMAIN/api/v2/users/USER_ID/roles' \
  -H 'Authorization: Bearer MGMT_API_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{ "roles": ["ROLE_ID"] }'
```

**上限（執筆時点の Entity Limit Policy）**: 1テナントあたりロール 1,000 個、1ユーザーに割り当てられるロール 50 個、1ロールあたりパーミッション 1,000 個。なおユーザーに直接割り当てるパーミッションには上限がありますが、**複数のロールに分けて持たせれば実効的にはその数を超えられます**。

### 4. Organization — B2B 用の「ユーザーの箱」

Organization は「**Auth0 テナント内でユーザーの集まりを構造化する仕組み**」で、B2B ユースケース向けに用意されています。取引先企業ごとにユーザーを分離し、企業ごとにブランディングやログインフロー（連携先 IdP）を変えられます。

- **メンバーの追加** — Dashboard > Organizations > 対象組織 > Members > Add members > Add Users。**あらかじめテナントにユーザーが存在している必要があります。** 見つからない場合は招待に切り替えます。Management API では Create Organization Members エンドポイントに POST します。
- **招待** — Create Organization Invitations エンドポイントに POST。Auth0 がメールで招待を送るか、**招待 URL だけを生成して自分で配る**かを選べます。**招待の作成時にロール ID を同時に指定できます。**
- **Connection の有効化** — 組織ごとに使える Connection を選べます。有効化するとその組織のログイン画面に選択肢として出ます。
- **自動メンバー化（Membership On Authentication）** — 有効にすると、その Connection でログインしたユーザーを自動的にその組織のメンバーにします。SSO で入ってきた企業ユーザーをいちいち手で追加しなくて済みます。

```mermaid
graph LR
  A["管理者が招待を作成<br>（メール or 招待URL／ロールも同時指定可）"] --> B["ユーザーが招待URLから<br>組織のログイン画面へ"]
  B --> C["有効化されたConnectionで認証"]
  C --> D["メンバーになる<br>（招待受諾 or 自動メンバー化）"]
  D --> E["組織スコープのロールが有効になる<br>（招待時指定 or 後から付与）"]
  E --> F["発行されるトークンに<br>org_id クレームが入る"]
```

上図は招待からトークン発行までの流れです。最後の `org_id` が効き所です。

### 5. 組織スコープのロール — 「A社では管理者、B社では一般ユーザー」

ここが Auth0 のロール設計のおもしろいところです。ロールには2つの効き方があります。

- **テナントレベルのロール** — テナント全体に対して割り当てる、いわば素のロール。
- **組織スコープのロール** — 同じロールを「**その組織のメンバーとして**」割り当てる。ユーザーがその組織でログインしたときにだけ適用されます。

つまり **1人のユーザーが、A社では privileged なロールを持ち、B社では持たない** という状態を素直に表現できます。マルチテナントの SaaS を作るときに必要になる考え方です。

組織メンバーへのロール付与手順:

- **Dashboard** — Organizations > 対象組織 > Members > メンバー名 > **Assign role** > ロール名を入力 > Add role(s) to organization。
- **Management API** — Create Organization Member Roles エンドポイントに POST。
- **前提** — 付与したいロールが**あらかじめテナントに作成されている**必要があります（組織側でロールを新規作成するのではなく、テナントのロールを組織メンバーに紐づける形）。

そして組織メンバーであるユーザーに発行されるトークンには、**アクセストークンにも ID トークンにも `org_id` クレームが自動的に付きます。** アプリ側はこれを見て「今どの組織の文脈でログインしているか」を判断します。

## つまずきやすいところ・注意点

- **標準機能に「グループがない」を早めに受け入れる。** Entra ID / Okta / Ping の感覚で Groups メニューを探すと迷子になります。人の分類は Organization、権限の束は Role、それ以外の独自分類は app_metadata、と役割を分けて考えます。
- **RBAC は API ごとのトグル。** テナント全体で一括オンにするものではありません。「ロールを作ったのにトークンに権限が出ない」ときは、まず対象 API の Enable RBAC と Add Permissions in the Access Token を確認します。
- **自動メンバー化には前提条件がある。** Auth0 のサポート記事によれば、この機能はアプリケーションの **Types of users が Business only** に設定されている場合にのみ動作し、**Both** の場合は自動メンバー化のロジックが走りません。
- **`user_metadata` は本人が書き換えられる。** 認可の判断材料をここに置いてはいけません。それは `app_metadata` の仕事です。
- **Universal Login の組織ピッカーには表示上限がある。** サポート記事では、ユーザーが所属する組織のうちログイン画面のピッカーに出るのは **20 件まで**とされています。所属組織が多くなる設計では、`organization` パラメータを明示するなど別の入口を用意する必要があります。
- **上限値は変わる。** 本記事の数値は執筆時点の Entity Limit Policy に基づきます。Enterprise プランでは組織数・組織メンバー数の上限引き上げをサポート経由で申請できます（公式が挙げる 2,000,000 という数字は**デフォルト上限ではなく、申請後に引き上げられる上限**です）。実装前に必ず最新のポリシーページを見てください。

## 今日のまとめ

### 重要用語ミニ辞書

- **Connection（接続）** — Auth0 とユーザーのソースとの関係。Database / Social / Enterprise の3系統。
- **Database Connection** — ID とパスワード（またはパスキー）で認証する Connection。資格情報は Auth0 のユーザーストアか自前 DB に置く。
- **root 属性** — `email`、`name` などプロファイル直下の標準属性。
- **user_metadata** — 中核機能に影響しない属性。本人が変更できる。
- **app_metadata** — 中核機能に影響する情報。本人は変更できない。
- **Permission（権限）** — API に対して定義する操作単位。
- **Role（ロール）** — ユーザーに適用できる Permission の集まり。
- **Organization（組織）** — テナント内でユーザーの集まりを構造化する B2B 向けの箱。
- **組織スコープのロール** — その組織のメンバーとしてログインしたときだけ効くロール。
- **`org_id` クレーム** — 組織メンバーに発行されるトークンに自動で入る、組織を示すクレーム。

### 理解度チェック

1. Auth0 の標準機能に「グループ」がない代わりに、ユーザーをまとめる仕組みは何が用意されているか。それぞれの役割の違いを説明できるか。
2. `user_metadata` に「このユーザーは管理者かどうか」のフラグを置くと、なぜ危ないのか。
3. ロールを作ってユーザーに割り当てたのに、アクセストークンに権限が載ってこない。どこを疑うか（2箇所）。

## 参考リンク

- [Auth0 Database Connections](https://auth0.com/docs/authenticate/database-connections)
- [Identity Providers（Connections）](https://auth0.com/docs/connections)
- [Understand How Metadata Works in User Profiles](https://auth0.com/docs/manage-users/user-accounts/metadata)
- [Enable Role-Based Access Control for APIs](https://auth0.com/docs/get-started/apis/enable-role-based-access-control-for-apis)
- [Role-Based Access Control](https://auth0.com/docs/manage-users/access-control/rbac)
- [Add Permissions to Roles](https://auth0.com/docs/manage-users/access-control/configure-core-rbac/roles/add-permissions-to-roles)
- [Assign roles to a user（Management API）](https://auth0.com/docs/api/management/v2/users/post-user-roles)
- [Auth0 Organizations（概要）](https://auth0.com/docs/manage-users/organizations)
- [Assign Members to an Organization](https://auth0.com/docs/manage-users/organizations/configure-organizations/assign-members)
- [Send Organization Membership Invitations](https://auth0.com/docs/manage-users/organizations/configure-organizations/send-membership-invitations)
- [Enable Organization Connections](https://auth0.com/docs/manage-users/organizations/configure-organizations/enable-connections)
- [Add Roles to Organization Members](https://auth0.com/docs/manage-users/organizations/configure-organizations/add-member-roles)
- [Work with Tokens and Organizations（org_id の自動付与）](https://auth0.com/docs/manage-users/organizations/using-tokens)
- [Single Identity Provider: Authorization](https://auth0.com/docs/get-started/architecture-scenarios/multiple-organization-architecture/single-identity-provider-organizations/authorization)
- [Authorization Extension（レガシー／Groups を持つ）](https://auth0.com/docs/customize/extensions/authorization-extension)
- [Entity Limit Policy](https://auth0.com/docs/troubleshoot/customer-support/operational-policies/entity-limit-policy)
- [Organization Auto-membership Feature Requirements（Auth0 サポート）](https://support.auth0.com/center/s/article/organization-auto-membership-feature-requirements)
- [Limit of 20 Organizations on Universal Login Page Organization Picker（Auth0 サポート）](https://support.auth0.com/center/s/article/Limit-of-20-Organizations-user-is-a-member-of-on-Unviersal-Login-page-Organization-Picker)
