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

重建时会执行插件迁移并创建 18 张 `ingenic_*` 数据表。通常需要几分钟，
重建期间论坛会暂时无法访问。`discourse_docker` 的普通 rebuild 不提供零停机。

这里必须用 **rebuild**，不能只重启容器：这次新增了首页控制器和路由，
而 Discourse 只在启动时读取插件的文件。只更新主题是另一种情况——
上传主题 zip 完全不需要重建。

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

1. 打开主题并选择 **Ingenic Light** 配色方案。强调色在这个配色方案中，
   可以使用 Discourse 标准颜色选择器修改；没有单独的颜色设置。
   配色方案内置的是天空淡蓝色：强调色 `#2FC1FF`、正文 `#12263a`、
   顶栏 `#f2f9fd`、高亮 `#cfe8fb`。如果顶栏是灰色而不是淡蓝，
   说明主题仍在用站点原有配色方案，这一步没做。

   这个强调色是刻意调淡的，因此它是"面"而不是"字"。主题自己处理了这个
   问题：链接和按钮文字用的是同色系中更深一档的颜色（见主题 README 的
   **Colours** 一节）。如果你把强调色改深，主题照样能用，只是链接颜色
   会比它需要的更深。
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
| `ingenic_points_enabled` | 开启；如果还没准备好上线可以关闭 |
| `ingenic_points_exclude_staff` | 开启 |
| `ingenic_bounties_enabled` | 开启；在允许成员挂悬赏之后再打开 |
| `ingenic_bounty_min_points` | 10 |
| `ingenic_bounty_max_points` | 1000 |
| `ingenic_bounty_expiry_days` | 14 |

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

`ingenic_points_enabled` 是整个积分系统的总开关。关闭后，论坛不再发放积分，
标了价的资源对所有已获准的账号都免费。它不会清空流水账：已有的流水和余额原样保留，
重新打开后从当前状态继续累计。关闭期间，管理员手工调整积分仍然可用——那是"有人
有意为之"，与"论坛自动决定"是两件事。

`ingenic_points_exclude_staff` 决定管理员和版主是否参与积分。默认开启（即不参与），
理由是：在这里回答问题属于站务人员的本职工作，而不是他们的社区贡献；而且一个社区
里没人能登顶的排行榜意义不大。试用这个功能时需要注意：用版主账号发帖测试会
"什么都看不到"。这个设置不阻止站务人员"给出"积分——版主点的赞，对被点赞的作者
仍然照常计分。

两个设置都可以随时修改。把 `ingenic_points_exclude_staff` 关掉不会追溯补发站务
人员之前发过的帖子，只对之后的帖子生效。

`ingenic_bounties_enabled` 允许成员在自己的主题上挂出积分悬赏，采纳答案后全额
支付给答主。它依赖积分系统和已解决插件，两者任一关闭时它也会自动关闭——悬赏本质
是积分在流动，而结算依据是已解决插件的那个 ✓。关闭它只会停止接受新的悬赏，已经
挂出的悬赏仍会到期并退回：这是有意为之，一个用来"停止新悬赏"的开关不应该把已经
托管的积分卡死。

`ingenic_bounty_min_points` 和 `ingenic_bounty_max_points` 是成员可以挂出的积分
区间。`ingenic_bounty_expiry_days` 是悬赏的挂出天数，到期后自动结束并把积分退回
给挂出悬赏的成员——要让"回答"这件事比悬赏本身更快。没有按版块区分的设置：悬赏
属于主题，主题归属哪个版块只是附带信息。

开启前需要知道的一点：积分是**托管**的。成员挂出 500 积分的悬赏后，在悬赏结束
之前他就少了 500 积分可用于下载解锁。这是机制本身而不是副作用——正是它挡住了
"同一个人把同样的 500 积分挂在十个问题上"——但也是第一次使用时最容易让人意外的
地方。

`ingenic_nav_items` 和 `ingenic_homepage_blocks` 都是 JSON 配置，可选填。
如果 `ingenic_nav_items` 留空，主题会使用自带的默认导航：在线文档、下载中心、
开发板、高分悬赏、积分。

**一旦配置了 `ingenic_nav_items`，它会整体替换主题自带的列表**，而不是与之合并。
因此在悬赏功能上线之前就已经配置过导航的站点，不会有"高分悬赏"入口，也不会自动
多出一个：需要自己在 JSON 里补上，或者清空这个设置、以上面的列表为起点重新配置。

一个可直接修改的 `ingenic_nav_items` 示例：

```json
[
  { "key": "home",      "label": "Home",                  "icon": "house",     "href": "/",                    "position": 0, "enabled": true },
  { "key": "announce",  "label": "Official Announcements", "icon": "bullhorn", "category": "official-announcements", "position": 1, "enabled": true },
  { "key": "discuss",   "label": "Technical Discussions",  "icon": "comments",  "category": "technical-discussions",  "position": 2, "enabled": true },
  { "key": "docs",      "label": "Documentation",          "icon": "book",      "href": "/ingenic/docs",        "position": 3, "enabled": true },
  { "key": "downloads", "label": "Downloads",              "icon": "download",  "href": "/ingenic/downloads",   "position": 4, "enabled": true },
  { "key": "boards",    "label": "Development Boards",     "icon": "microchip", "href": "/ingenic/boards",     "position": 5, "enabled": true },
  { "key": "bounties",  "label": "Bounties",               "icon": "gift",      "href": "/ingenic/bounties",   "position": 6, "enabled": true },
  { "key": "points",    "label": "Points",                 "icon": "star",      "href": "/ingenic/points",     "position": 7, "enabled": true }
]
```

使用 `category` 的导航项会自动解析为 `/c/<分类 slug>`，因此可以把导航指向
论坛分类，而不必直接填写 URL。每个芯片产品可以设置自己的论坛分类和对应的
`/ingenic/docs/<product>` 文档入口。

一个可直接修改的 `ingenic_homepage_blocks` 示例：

```json
[
  { "type": "categories",    "enabled": true, "position": 0 },
  { "type": "bounties",      "enabled": true, "position": 1, "limit": 4 },
  { "type": "promotions",    "enabled": true, "position": 2 },
  { "type": "announcements", "enabled": true, "position": 3, "limit": 5,  "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 4, "limit": 10, "category": "technical-discussions" },
  { "type": "downloads",     "enabled": true, "position": 5, "limit": 6 },
  { "type": "boards",        "enabled": true, "position": 6, "limit": 4 }
]
```

`promotions` 对应在 **Ingenic → Site → Promotions** 中维护的活动推广位；没有配置
任何活动时该模块不显示。`bounties` 模块列出积分最高的进行中悬赏，没有悬赏时不
显示任何内容，所以从第一天起就可以一直开着。如果填入的类型名没有对应的组件，该
模块同样不会显示，所以写错名字的表现是"一直不出现"。

### 首页

插件把首页作为一个**首页选项**提交给 Discourse，所以这里设置的是 Discourse 自己的
一项核心设置，而不是插件设置：

| 设置 | 取值 | 作用 |
|---|---|---|
| `default_homepage` | Ingenic 首页（实际存储值为 `ingenic-home`） | 让 `/` 成为首页 |

在 **管理后台 → 设置 → 界面** 中设置，或用命令行：

```bash
./launcher enter app
rails c
SiteSetting.default_homepage = "ingenic-home"
```

只有 `ingenic_enabled` 开启时这个选项才会出现在列表里。如果站点已经选中它、之后又
关掉了插件，站点会回落到普通首页，而不是报错。

首页的内容是：一个横幅、五个工具页面入口（在线文档、下载中心、开发板商店、高分
悬赏、积分），然后是首页模块。它**不是**主题列表，也没有自己的最新/热门/新帖标签
页——那些标签属于主题列表，而主题列表现在在别的地方。在导航里选择 **最新** 会进入
最新主题列表，首页仍然在原处；在此之前，首页是画在主题列表上方的，一切换标签就跟着
消失了。

首页自己的地址是 `/ingenic/home`，因此可以直接写进链接，刷新也仍然是同一个页面。

一个可直接修改的 `ingenic_homepage_blocks` 示例——版块网格加悬赏版块，这也是留空
时的默认效果：

```json
[
  { "type": "categories", "enabled": true, "position": 0, "limit": 8 },
  { "type": "bounties",   "enabled": true, "position": 1, "limit": 4 }
]
```

`categories` 把论坛版块以卡片形式列出，每张卡片进入对应版块。加
`"categories": ["official-announcements", "technical-discussions"]` 可以指定显示哪些
版块及其顺序；不加则按主题数取最活跃的一级版块，数量由 `limit` 决定。
`"show_all": false` 会去掉标题末尾的 **所有版块** 链接。

`bounties` 列出积分最高的进行中悬赏；没有悬赏时它什么都不显示——没有标题，也没有
空行——所以在论坛还没用起悬赏之前一直开着也没有副作用。默认模块里带上它，正是这个
原因。

如果想同时保留公告和技术讨论模块，把它们排在后面：

```json
[
  { "type": "categories",    "enabled": true, "position": 0, "limit": 8 },
  { "type": "bounties",      "enabled": true, "position": 1, "limit": 4 },
  { "type": "announcements", "enabled": true, "position": 2, "limit": 5, "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 3, "limit": 6, "category": "technical-discussions" }
]
```


### 界面语言

界面语言是 Discourse 自带的能力，所以下面三项是核心设置，不是插件设置。它们决定
页头的语言切换器能不能用：

| 设置 | 取值 | 原因 |
|---|---|---|
| `default_locale` | `en` | 首次访问的访客看到的语言 |
| `allow_user_locale` | 开（默认已经是开） | 关闭后任何人都不能选择语言，切换器会自动隐藏 |
| `set_locale_from_cookie` | 开 | 未登录访客的选择保存在 cookie 里；这一项关闭时 Discourse 不会回读该 cookie，表现就是"点了没反应" |

切换器位于页头最右侧——未登录时在 **登录** 按钮左边，已登录时在头像左边——提供的
语言来自主题设置 `ingenic_locales`，默认为 `en|zh_CN`。每一项都用该语言自己的写法
显示，所以看不懂当前界面语言的访客也能找到自己要选的那一项。

Discourse 把语言记在两个地方，切换器写的是当前生效的那一个：已登录账号使用账号自己
的语言偏好（在个人偏好设置里也能改），未登录访客则读 cookie。已登录的访客不会读
cookie——这是 Discourse 的规则，不是插件的行为。

### 页面底部

在主题自己的页脚（第三方平台区与链接列，在 **Ingenic → Site** 中配置）下面，
Discourse 还会画一行自己的内容：**由 Discourse 提供技术支持**，它出现在大多数页面的
最底部。隐藏它只需要改一项核心设置，不需要动主题：

| 设置 | 取值 | 原因 |
|---|---|---|
| `enable_powered_by_discourse` | 关闭 | 去掉 **由 Discourse 提供技术支持** 这一行，页面就结束在本站自己的页脚 |

位置在 **管理后台 → 设置 → 站点管理员**，也可以在设置页直接搜索 `powered by`
（搜索框匹配的是设置项名称与英文说明，中文界面下也建议用 `powered by`）。主题自己的
页脚是另一回事——它由 **Ingenic → Site** 配置，不受这一项影响。

### 主题设置

| 设置 | 默认值 | 作用 |
|---|---:|---|
| `ingenic_locales` | `en\|zh_CN` | 页头切换器提供的语言；少于两项时切换器不显示 |
| `ingenic_sidebar_width` | 272 | 桌面端侧边栏宽度，单位为像素 |
| `ingenic_sidebar_position` | `left` | 侧边栏位置，可改为 `right` |
| `ingenic_nav_order` | `first` | Ingenic 导航位于 Discourse 原生区段之前或之后 |
| `ingenic_nav_title` | 空 | 导航上方的可选标题；留空时显示无标题列表 |
| `ingenic_hero_title` | 空 | 首页模块上方的可选标题 |
| `ingenic_hero_subtitle` | 空 | 首页标题下方的可选说明 |

---

## 4. 录入内容

在线文档、下载资源、开发板、积分、范围权限和站点首页内容都可以直接在 Discourse 管理后台维护，不必每次进入 Rails 控制台。进入 **管理后台 → 插件 → Ingenic**，这里有六个标签页。管理员可以看到全部六个标签页；版主，以及只被授予某个产品或某块开发板范围权限的账号，只会看到该权限覆盖的两个页面（Documentation 和 Development boards），其余四个页面在服务端就限定为管理员，不给入口好过给一个点进去会被拒绝的链接。另外，Discourse 自己的“插件”页面仅限站务人员访问，因此打开这些页面的实际操作者是管理员或版主。

**Documentation（在线文档）**：管理产品树（系列 → 型号）、每个产品的版本，以及某个版本下的页面树。在某个版本中编辑过的页面，可以在之后的版本中选择覆盖；没有覆盖的页面会从上一个版本继承，因此新建版本相当于自动沿用上一版的内容，不需要手工复制。编辑器会标明当前页面来自哪个版本，并提供 **Override in this version**（在本版本中覆盖）和 **Restore inheritance**（恢复继承）。

后台界面目前只有英文语言包，中文界面下会回退显示英文，上面的按钮名称即为实际显示的文字。

**Downloads（下载中心）**：内部还有五个标签页。*Resources* 是资源目录，维护名称、产品、版本、平台、分类、文件（上传或外部链接）、发布日期和访问级别。*Applications* 是需要审核的申请队列，显示申请人填写的开发者信息，可以批准或驳回。*Access* 是当前持有下载授权的账号，可以撤销。*Download record* 是"谁在什么时候下载了什么"的记录。*Categories* 是可增删改的资源分类列表，可以新增、改名、调整顺序和停用。

**Boards（开发板）**：维护开发板卡片，包括图片、芯片、简介、规格、文档链接和 **Buy now（立即购买）** 链接。

**Permissions（权限）**：文档的范围权限。授予 T 系列后，该用户可以管理 T 系列下的版本和页面；只授予 T33 时，不能管理 T32 或 T 系列父级。授权对象可以是用户或群组。服务端会对所有新增、修改、删除请求再次校验，前端隐藏按钮不是权限边界。

**Points（积分）**：成员通过贡献获得的积分，以及下载资源可以标价消耗的积分。同一个页面分四块。*What earns points* 是价目表：每个动作值多少分、在成员记录里显示成什么名称、显示顺序，以及论坛是否还发放它。*Adjust one account* 手工调整某个账号的积分，按用户名挑选，填写的备注会成为流水记录上的原因。*Repair the balances* 依据流水重新计算所有余额，用于两者对不上的情况——流水是记录，余额只是它的缓存。*Recent movements* 是最近一百条流水，上方的 *Balances* 列出当前谁持有多少积分。

这个页面**连查看也是仅限管理员**的，不只是修改：流水账里会出现账号名，而一次调整会改变某个成员在站内的状态。产品或开发板的范围权限到不了这里——积分余额不属于任何产品或开发板。

**Site（站点）**：站点中属于"内容"而不是"论坛"的三部分，分三个标签页。*Promotions* 是首页的活动推广位，每项包含图片、标题和跳转地址。*Partner platforms* 是页脚的第三方平台区，每一项可以是跳转链接，也可以是二维码图片——网页类平台用链接，App 类平台用二维码让访客扫码。*Footer columns* 是页脚链接列，列数不限，每列有自己的标题和按顺序排列的链接。

### 下载访问级别

每个资源属于三个级别之一。判断在文件接口上执行，而不是在页面上执行，因此按钮和文件本身不会出现不一致。

| 级别 | 访客需要先完成什么 |
|---|---|
| `public_login` | 登录 |
| `login_form` | 登录，并已填写开发者信息 |
| `login_form_request` | 登录、已填写开发者信息，并且申请已通过审核 |

开发者信息只需要填写一次，之后所有受限资源共用，不是每个文件填一次。审核通过后授权长期有效（授权记录没有到期时间），所以"谁下载过"以日志为准，而不是以授权记录为准。访客没有被放行的资源不会在页面上出现任何直链，列表只给出插件接口地址，由接口决定是否放行。

### 资源标价

在访问级别之上，资源还可以带一个**积分价格**，在 **Ingenic → Downloads → Resources** 的同一个表单里设置。默认值 0，表示免费。

价格是在访问级别**之后**才询问的，而不是替代它：一个标价 500 分、级别为 `login_form_request` 的资源，对于新访客仍然是先登录、先填开发者信息、先通过审核，然后才会提到积分。没有被放行的账号，出多少分都买不到。

购买记录是一条流水，而不是在别处新增一个字段，这正是它具备幂等性的原因：买过之后，无论下载多少次都不会重复扣分；即使之后余额被花到 0，这次购买依然算数。积分足够时列表显示 **Unlock for N points**，不够时显示 **Needs N points**，所以按钮不会给出接口会拒绝的承诺。

扣分只发生在文件接口中**真正把文件发出去**的那个分支，绝不会发生在"报告资源不可用"的分支——所以一个从存储里找不到的文件不会扣任何积分。

积分通过贡献获得：发起讨论、回帖、帖子被点赞、回答被采纳。这四个动作也各自有对应的事件，在帖子被删除、点赞被取消、采纳被撤销时把积分收回来。成员在 **`/ingenic/points`** 可以看到自己的余额、价目表和自己的变动记录；这个页面在前端是只读的——积分靠贡献获得、靠下载消耗，这两件事都不通过这个地址发生。未登录的访客也能看到价目表，所以这个页面对他们是一个回答，而不是一扇锁着的门。

积分是插件功能，页面入口由主题提供。主题自带一个"积分"入口；如果站点已经配置了自己的 `ingenic_nav_items`，需要自己补上这一项。

插件目录中的 `docs/seeding.md` 包含四类内容（文档、下载、开发板、积分）的完整录入示例，适合首次导入和批量初始化。中文版见 `docs/seeding.zh-CN.md`，两份内容一致，交给实际执行录入的人用中文那份即可。

进入 Rails 控制台：

```bash
cd /var/discourse
./launcher enter app
rails c
```

然后按照 `docs/seeding.md`（或中文版 `docs/seeding.zh-CN.md`）创建产品、版本和文档页面。

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
- [ ] 普通成员发帖后余额发生变化，**Ingenic → Points → Recent movements** 中能看到这条流水
- [ ] 删除该帖后积分被收回，且原来那条奖励记录仍然留在流水账中，与收回记录并列可见
- [ ] 给某个资源设置了积分价格后，余额足够的账号看到 **Unlock for N points**，不足的看到 **Needs N points**
- [ ] 购买时扣一次分；同一个资源第二次下载不再扣分
- [ ] `/ingenic/points` 向已登录成员显示自己的余额、价目表和自己的变动记录，且看不到别人的
- [ ] 管理员手工调整某个账号后余额随之变化，填写的备注成为该条流水的原因
- [ ] 关闭 `ingenic_points_enabled` 后，标价资源免费下载且不再发放积分；重新打开后余额仍在
- [ ] 在自己的主题上，**为本帖挂出悬赏** 会显示可挂区间和当前余额；挂出后积分立即从余额中扣除，**Ingenic → Points** 中能看到这部分被托管
- [ ] 进行中的悬赏会同时显示在主题页、首页悬赏版块和 `/ingenic/bounties` 上；不是本人的访问者看不到撤回入口
- [ ] 在该主题采纳答案后，积分全额支付给答主、悬赏关闭，主题上会显示支付了多少、支付给了谁
- [ ] 撤回进行中的悬赏会把积分退回；无人回答的悬赏在 `ingenic_bounty_expiry_days` 到期后的一个小时内自动退回
- [ ] `/ingenic/boards` 显示开发板，配置了购买链接的卡片会显示 **Buy now** 按钮
- [ ] 页头最右侧出现语言切换器——未登录时在 **登录** 按钮旁，已登录时在头像旁；选 **中文** 后页面以中文重新加载，选 **English** 能切回
- [ ] 登录状态下的切换同样有效——该选择在退出再登录后依然保留
- [ ] Ingenic 导航出现在 Discourse 侧边栏中，移动端抽屉中也能看到
- [ ] 把文档地址复制到新浏览器标签页，可以直接打开
- [ ] `/` 就是首页：横幅、五个工具入口、版块卡片，且**没有**主题列表，也没有最新/热门标签页
- [ ] 在导航里选 **最新** 会进入主题列表，返回首页时首页仍然在
- [ ] 版块模块标题末尾的 **所有版块** 链接进入 `/categories`
- [ ] 点击版块卡片会进入对应分类
- [ ] 如果配置了 `promotions` 模块，**Ingenic → Site** 中配置的活动推广位出现在首页
- [ ] 页脚显示第三方平台区（网页类为链接、App 类为可扫描的二维码）以及配置好的链接列
- [ ] 关闭 `enable_powered_by_discourse` 后，页面结束在该页脚处，底部不再有 **由 Discourse 提供技术支持**
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

## 7. 把配置搬到另一台机器

本论坛的配置由两部分组成：插件的设置与内容，以及主题的设置。两者分开导出，因为它们
属于不同的对象。

### 主题设置

**管理后台 → 自定义 → 主题 → Ingenic Community → 导出** 会生成一个 zip，其中
settings 字段带的是主题当前的值，所以在另一台机器上导入这个 zip 就能带上主题设置。
zip 里没有别的——主题的文件来自本仓库。

### 插件设置与内容

```bash
cd /var/www/discourse

# 把这个插件拥有的全部配置写进一个文件
rake ingenic:export_config[/shared/ingenic-config.yml]

# 只看文件里有什么，不改动任何数据
rake ingenic:show_config[/shared/ingenic-config.yml]

# 应用它——第二个参数表示执行后整体回滚
rake ingenic:import_config[/shared/ingenic-config.yml,dry]
rake ingenic:import_config[/shared/ingenic-config.yml]
```

文件里包含插件的站点设置（你改过的那些，仍处于默认值的不会写进去），以及管理员在后台
录入的内容：产品树、版本、页面、下载目录与分类、开发板、文档权限、活动推广位、页脚、
社交链接和积分规则。

文件里**刻意不包含任何成员产生的数据**。积分余额、积分流水、高分悬赏、下载申请、
授权记录、开发者资料、下载记录，记录的都是人做过什么，其中开发者资料还是个人信息。
那些东西属于数据库备份，是另一类副本、另一套保管方式，需要的话请直接做数据库备份。

`import_config` 按自然键 upsert——产品由 slug 与语言标识，版本由所属产品与 slug 标识，
依此类推——所以同一个文件导入两次，第二次不会有任何改动。它从不删除：存在于论坛但不在
文件里的记录会原样保留，并在结尾以 `Left alone` 列出，由你决定怎么处理。整个导入在一个
事务里完成，文件被拒绝时论坛保持原样。

上传的 SDK 与固件文件本身也不在文件里，只有指向它们的记录，包括每个文件被写入的路径。
把下载目录一起拷过来的机器可以直接恢复出可用的下载中心；没有那些文件的机器会得到指向
不存在文件的记录。

### 每次部署之后

```bash
rake ingenic:doctor
```

它会检查那几个"设错了也不会报错"的设置——插件被关掉、没人能切换语言、下载目录不可写
——并指出需要改哪一项。

---

## 8. 当前验证范围

本项目尚未在真实运行中的 Discourse 实例执行。当前构建环境没有 Ruby、bundler
和数据库，因此：

- 插件 RSpec 测试已经编写，但尚未实际运行；
- 主题尚未经过 Discourse 的完整资源编译流程；
- 尚未在浏览器中进行实际渲染测试；
- 悬赏数据表尚未由 migration 真正建出，每小时运行一次的到期任务也从未触发过——
  托管、支付、退回三条路径都有测试覆盖，但还没有真实积分流动过。

已经完成的校验包括：

- 使用 Babel 和 Glimmer 解析主题 JavaScript；
- 使用 tree-sitter 解析 Ruby；
- 解析所有 YAML 配置和 locale 文件；
- 对照 Discourse `2026.10.0-latest` 源代码确认所使用 API 的签名和行为，
  包括 `api.addSidebarSection`、侧边栏区段基类、主题路由表合并顺序、主题设置
  到 SCSS 变量的注入链路。

第一次 rebuild 和浏览器验证是最终的实机测试。如果主题出现编译错误，管理后台
的主题页面会显示具体文件和行号，将错误信息发回即可继续修复。
