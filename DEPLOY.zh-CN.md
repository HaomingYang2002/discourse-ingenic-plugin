# Ingenic 社区主题和插件部署说明

本项目包含两个需要分别安装的部分：

| 部分 | 作用 | 安装方式 |
|---|---|---|
| `discourse-ingenic` | Rails 插件：在线文档、下载中心、开发板、站点设置 | 放入 `plugins/` 后重建 Discourse |
| `discourse-ingenic-theme` | 主题：布局、导航、首页、文档界面 | 上传 zip 文件，不需要重建 |

本项目不会修改登录认证。Google、GitHub 和邮箱登录仍然按照当前
Discourse 的配置运行。

目标版本：Discourse `2026.10.0-latest`。主题和插件均按照这个版本的源代码开发
并完成了静态校验。

---

## 1. 安装插件

### 方式 A：从 Git 仓库安装（推荐）

把 `discourse-ingenic` 放进服务器可以访问的 Git 仓库，然后在
`containers/app.yml` 中增加：

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://<你的-git-地址>/discourse-ingenic.git
```

将 `<你的-git-地址>` 替换成你们自己的仓库地址。

### 方式 B：直接复制文件

在本地执行：

```bash
scp -r discourse-ingenic <用户名>@<服务器>:/tmp/discourse-ingenic
```

然后在服务器上执行：

```bash
sudo mv /tmp/discourse-ingenic /var/discourse/plugins/discourse-ingenic
```

这里的 `<用户名>`、`<服务器>` 由部署人员在服务器上自行填写，不需要发给我。

### 重建 Discourse

```bash
cd /var/discourse
./launcher rebuild app
```

重建时会执行插件迁移并创建 15 张 `ingenic_*` 数据表。通常需要几分钟，
重建期间论坛会暂时无法访问。`discourse_docker` 的普通 rebuild 不提供零停机。

进入容器确认插件已加载：

```bash
./launcher enter app
rails c
SiteSetting.ingenic_enabled          # 应为 true
IngenicDocProduct.count              # 尚未录入内容时应为 0
```

---

## 2. 安装主题

进入：

**管理后台 → 自定义 → 主题 → 安装 → 从文件安装**

上传：

```text
discourse-ingenic-theme.zip
```

然后：

1. 打开主题并选择 **Ingenic Light** 配色方案。品牌强调色在这个配色方案中，
   可以使用 Discourse 标准颜色选择器修改；没有单独的品牌颜色设置。
2. 可以直接把它设置为网站默认主题，也可以先作为可选主题，确认效果后再切换。

这是完整主题，不是组件，因此不需要另外安装组件。

---

## 3. 安装后的设置

### 插件站点设置

在管理后台的插件设置中配置：

| 设置 | 建议值 |
|---|---|
| `ingenic_enabled` | 开启 |
| `ingenic_default_locale` | 文档主要使用的语言 |
| `ingenic_docs_discussion_category` | 文档讨论所属分类的 slug |
| `ingenic_download_storage_path` | 大容量卷上的目录，必须位于 `public/` 之外；留空则使用 `<app>/ingenic-downloads` |
| `ingenic_download_admin_email` | 接收下载申请通知的邮箱 |
| `ingenic_developer_form_fields` | JSON 配置；留空则使用内置的开发者信息表单 |
| `ingenic_official_groups` | 需要显示官方认证图标的群组名称，例如 `admins` |

`ingenic_download_storage_path` 决定上传的 SDK 和固件存放在哪里。这个目录必须
放在 `public/` 之外：如果文件能被 Web 服务器直接访问，任何猜到地址的人都能下载，
插件再怎么做权限判断也没有意义，因此文件统一由插件转发。下载量增长后可以把
这个路径指向更大的数据盘。

`ingenic_download_admin_email` 是收到下载申请时发信的目标地址。留空时申请记录
仍然会写入并在后台申请列表中显示，只是不会发出邮件通知。

`ingenic_developer_form_fields` 用于替换内置的开发者信息表单，格式为 JSON 数组，
每一项包含 `key`、`label`、`type`、`required`，其中 `type` 取值为 `text` 或
`textarea`：

```json
[
  { "key": "full_name", "label": "Full name", "type": "text", "required": true },
  { "key": "use_case",  "label": "Intended use", "type": "textarea", "required": true }
]
```

访客看到的表单、提交时的必填校验、后台查看答案的展示都来自这一份配置，因此三者
不会互相不一致。留空则使用内置字段。如果之后从配置中删除某个字段，已经填写的
答案会保留而不会被清空。

内置表单和上面的示例都不会询问手机号。账号本身已经有可用于联系的邮箱，而团队
不会去看的字段只会让开发者更容易放弃填写表单。

`ingenic_official_groups` 用于指定哪些群组的成员会在用户名旁显示官方认证图标。
每行填一个群组名称，写法与该群组自己的页面一致；大小写和多余空格不影响结果。
图标本身就是 Discourse 的群组 flair，可以在群组设置中上传图片或选择图标，这个
设置只决定"谁佩戴"。已经自己选择了其他图标的成员会保留自己的选择，也可以之后
在个人偏好页面自行切换到官方图标。填写多个群组相当于约定优先级：排在前面的群组
优先。图标还没准备好时也可以先填写这个设置——已列出但尚未配置 flair 的群组不会
授予任何图标，等到图片上传后图标会自动出现。

`ingenic_nav_items` 和 `ingenic_homepage_blocks` 都是 JSON 配置，可选填。
如果 `ingenic_nav_items` 留空，主题会使用自带的默认导航：主页、在线文档、
下载中心、开发板。

一个可直接修改的 `ingenic_nav_items` 示例：

```json
[
  { "key": "home",      "label": "Home",                  "icon": "house",     "href": "/",                    "position": 0, "enabled": true },
  { "key": "announce",  "label": "Official Announcements", "icon": "bullhorn", "category": "official-announcements", "position": 1, "enabled": true },
  { "key": "discuss",   "label": "Technical Discussions",  "icon": "comments",  "category": "technical-discussions",  "position": 2, "enabled": true },
  { "key": "docs",      "label": "Documentation",          "icon": "book",      "href": "/ingenic/docs",        "position": 3, "enabled": true },
  { "key": "downloads", "label": "Downloads",              "icon": "download",  "href": "/ingenic/downloads",   "position": 4, "enabled": true },
  { "key": "boards",    "label": "Development Boards",     "icon": "microchip", "href": "/ingenic/boards",     "position": 5, "enabled": true }
]
```

使用 `category` 的导航项会自动解析为 `/c/<分类 slug>`，因此可以把导航指向
论坛分类，而不必直接填写 URL。每个芯片产品可以设置自己的论坛分类和对应的
`/ingenic/docs/<product>` 文档入口。

一个可直接修改的 `ingenic_homepage_blocks` 示例：

```json
[
  { "type": "promotions",    "enabled": true, "position": 0 },
  { "type": "search",        "enabled": true, "position": 1 },
  { "type": "announcements", "enabled": true, "position": 2, "limit": 5,  "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 3, "limit": 10, "category": "technical-discussions" },
  { "type": "downloads",     "enabled": true, "position": 4, "limit": 6 },
  { "type": "boards",        "enabled": true, "position": 5, "limit": 4 }
]
```

`promotions` 对应在 **Ingenic → Site → Promotions** 中维护的活动推广位；没有配置
任何活动时该模块不显示。如果填入的类型名没有对应的组件，该模块同样不会显示，
所以写错名字的表现是"一直不出现"。

### 主题设置

| 设置 | 默认值 | 作用 |
|---|---:|---|
| `ingenic_sidebar_width` | 272 | 桌面端侧边栏宽度，单位为像素 |
| `ingenic_sidebar_position` | `left` | 侧边栏位置，可改为 `right` |
| `ingenic_nav_order` | `first` | Ingenic 导航位于 Discourse 原生区段之前或之后 |
| `ingenic_nav_title` | 空 | 导航上方的可选标题；留空时显示无标题列表 |
| `ingenic_hero_title` | 空 | 首页模块上方的可选标题 |
| `ingenic_hero_subtitle` | 空 | 首页标题下方的可选说明 |

---

## 4. 录入内容

在线文档、下载资源、开发板、范围权限和站点首页内容都可以直接在 Discourse 管理后台维护，不必每次进入 Rails 控制台。进入 **管理后台 → 插件 → Ingenic**，这里有五个标签页。管理员可以看到全部五个标签页；版主，以及只被授予某个产品或某块开发板范围权限的账号，只会看到该权限覆盖的两个页面（Documentation 和 Development boards），其余三个页面在服务端就限定为管理员，不给入口好过给一个点进去会被拒绝的链接。另外，Discourse 自己的“插件”页面仅限站务人员访问，因此打开这些页面的实际操作者是管理员或版主。

**Documentation（在线文档）**：管理产品树（系列 → 型号）、每个产品的版本，以及某个版本下的页面树。在某个版本中编辑过的页面，可以在之后的版本中选择覆盖；没有覆盖的页面会从上一个版本继承，因此新建版本相当于自动沿用上一版的内容，不需要手工复制。编辑器会标明当前页面来自哪个版本，并提供 **Override in this version**（在本版本中覆盖）和 **Restore inheritance**（恢复继承）。

后台界面目前只有英文语言包，中文界面下会回退显示英文，上面的按钮名称即为实际显示的文字。

**Downloads（下载中心）**：内部还有五个标签页。*Resources* 是资源目录，维护名称、产品、版本、平台、分类、文件（上传或外部链接）、发布日期和访问级别。*Applications* 是需要审核的申请队列，显示申请人填写的开发者信息，可以批准或驳回。*Access* 是当前持有下载授权的账号，可以撤销。*Download record* 是"谁在什么时候下载了什么"的记录。*Categories* 是可增删改的资源分类列表，可以新增、改名、调整顺序和停用。

**Boards（开发板）**：维护开发板卡片，包括图片、芯片、简介、规格、文档链接和 **Buy now（立即购买）** 链接。

**Permissions（权限）**：文档的范围权限。授予 T 系列后，该用户可以管理 T 系列下的版本和页面；只授予 T33 时，不能管理 T32 或 T 系列父级。授权对象可以是用户或群组。服务端会对所有新增、修改、删除请求再次校验，前端隐藏按钮不是权限边界。

**Site（站点）**：站点中属于"内容"而不是"论坛"的三部分，分三个标签页。*Promotions* 是首页的活动推广位，每项包含图片、标题和跳转地址。*Partner platforms* 是页脚的第三方平台区，每一项可以是跳转链接，也可以是二维码图片——网页类平台用链接，App 类平台用二维码让访客扫码。*Footer columns* 是页脚链接列，列数不限，每列有自己的标题和按顺序排列的链接。

### 下载访问级别

每个资源属于三个级别之一。判断在文件接口上执行，而不是在页面上执行，因此按钮和文件本身不会出现不一致。

| 级别 | 访客需要先完成什么 |
|---|---|
| `public_login` | 登录 |
| `login_form` | 登录，并已填写开发者信息 |
| `login_form_request` | 登录、已填写开发者信息，并且申请已通过审核 |

开发者信息只需要填写一次，之后所有受限资源共用，不是每个文件填一次。审核通过后授权长期有效（授权记录没有到期时间），所以"谁下载过"以日志为准，而不是以授权记录为准。访客没有被放行的资源不会在页面上出现任何直链，列表只给出插件接口地址，由接口决定是否放行。

插件目录中的 `docs/seeding.md` 仍包含三类内容的完整录入示例，适合首次导入和批量初始化。

进入 Rails 控制台：

```bash
cd /var/discourse
./launcher enter app
rails c
```

然后按照 `docs/seeding.md` 创建产品、版本和文档页面。

在至少创建一个已发布产品前，访问 `/ingenic/docs` 显示“文档不可用”是正常的，
不是部署错误。

### 语言代码注意事项

内容记录中的语言代码必须使用 Discourse 的格式：

```text
正确：zh_CN、pt_BR
错误：zh-CN、pt-BR
```

访问者的界面语言优先匹配；如果某个页面没有对应翻译，则使用
`ingenic_default_locale`。因此可以先翻译一部分页面，不需要一次性完成全部内容。
同一个页面 slug 在目录中只显示一次，不会因为存在中英文两条记录而重复显示。

---

## 5. 部署后验证

请逐项打开并检查：

- [ ] `/ingenic/docs` 能打开第一个已发布产品，并将地址替换为该产品的规范地址
- [ ] 系列 → 型号两级选择器正常联动，选中系列后型号列表随之收窄
- [ ] 文档目录树正常显示，上一页 / 下一页按顺序切换
- [ ] 版本选择器可以切换版本；如果目标版本有同名页面，应继续停留在该页面
- [ ] 在新版本中未编辑的页面显示的是上一版本的内容，编辑器标明该页面来自哪个版本
- [ ] `/ingenic/downloads` 可以按系列、型号、分类、版本、平台筛选
- [ ] `public_login` 资源登录后即可下载；`login_form_request` 资源会先要求提交申请
- [ ] 在后台批准申请后，该账号可以下载，且 **Ingenic → Downloads → Download record** 中能看到该账号
- [ ] `/ingenic/boards` 显示开发板，配置了购买链接的卡片会显示 **Buy now** 按钮
- [ ] Ingenic 导航出现在 Discourse 侧边栏中，移动端抽屉中也能看到
- [ ] 把文档地址复制到新浏览器标签页，可以直接打开
- [ ] `/` 在主题列表上方显示首页模块，以及在 **Ingenic → Site** 中配置的活动推广位
- [ ] 页脚显示第三方平台区（网页类为链接、App 类为可扫描的二维码）以及配置好的链接列
- [ ] `ingenic_official_groups` 中列出的群组成员，用户名旁显示对应图标；自己选择过其他图标的成员保留原图标
- [ ] Google、GitHub 和邮箱登录仍然正常
- [ ] **管理后台 → 自定义 → 主题** 没有主题编译错误

在容器中运行插件 RSpec：

```bash
bundle exec rspec plugins/discourse-ingenic/spec
```

这会执行插件接口测试，是检查后端接口最快的方式。

---

## 6. 回滚

### 回滚主题

进入：

**管理后台 → 自定义 → 主题**

把网站默认主题切回原来的主题即可。不需要 rebuild，也不会造成停机。

### 回滚插件

如果使用 Git 安装：

1. 从 `app.yml` 中删除 `git clone` 配置；或
2. 从 `/var/discourse/plugins/` 删除 `discourse-ingenic` 目录；
3. 执行：

```bash
cd /var/discourse
./launcher rebuild app
```

插件数据表会保留。它们全部以 `ingenic_` 开头，其他功能不会读取这些表，
保留它们不会影响现有论坛，并且之后重新安装插件时内容仍然存在。

---

## 7. 当前验证范围

本项目尚未在真实运行中的 Discourse 实例执行。当前构建环境没有 Ruby、bundler
和数据库，因此：

- 插件 RSpec 测试已经编写，但尚未实际运行；
- 主题尚未经过 Discourse 的完整资源编译流程；
- 尚未在浏览器中进行实际渲染测试。

已经完成的校验包括：

- 使用 Babel 和 Glimmer 解析主题 JavaScript；
- 使用 tree-sitter 解析 Ruby；
- 解析所有 YAML 配置和 locale 文件；
- 对照 Discourse `2026.10.0-latest` 源代码确认所使用 API 的签名和行为，
  包括 `api.addSidebarSection`、侧边栏区段基类、主题路由表合并顺序、主题设置
  到 SCSS 变量的注入链路。

第一次 rebuild 和浏览器验证是最终的实机测试。如果主题出现编译错误，管理后台
的主题页面会显示具体文件和行号，将错误信息发回即可继续修复。
