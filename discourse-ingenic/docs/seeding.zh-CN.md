# 录入文档、下载资源与开发板

内容保存在插件自己的数据表中。日常编辑在 **管理后台 → 插件 → Ingenic** 中完成，
控制台（console）适合首次导入和批量操作。两条路径走的是同一套模型，因此这里
能建出来的记录，管理页面也一定能建出来，反之亦然。

```bash
cd /var/discourse
./launcher enter app
rails c
```

本文与英文版 `docs/seeding.md` 内容一致，可对照阅读。

## 产品树

其他所有内容都挂在这棵树上，所以先建它。产品分为 `series`（系列）和 `chip`
（型号）两种，形状由数据库约束保证：系列没有父级，型号的父级必须是系列。
`position` 决定两个层级内部的顺序。

这个区分是有实际作用的。在线文档的两级选择器、下载中心的系列与型号筛选、
开发板目录都读它，所以树建反了的表现是"筛选怎么点都筛不出东西"。

```ruby
series = IngenicDocProduct.create!(
  slug: "t-series",
  name: "T Series",
  kind: "series",
  locale: "en",
  description: "Vision SoCs for cameras and set-top boxes",
  position: 0,
)

chip = IngenicDocProduct.create!(
  slug: "t32pro",
  name: "T32Pro",
  kind: "chip",
  parent: series,
  locale: "en",
  position: 0,
)
```

## 在线文档

版本挂在型号下，页面挂在版本下。页面的 `parent_id` 用来构建左栏目录树，
一个有子页面的页面就成为一个可折叠的分组。

```ruby
latest = IngenicDocVersion.create!(
  product: chip,
  slug: "2.1.0",
  label: "2.1.0",
  locale: "en",
  latest: true,
  released_on: Date.new(2026, 9, 1),
  position: 0,
)

previous = IngenicDocVersion.create!(
  product: chip,
  slug: "2.0.0",
  label: "2.0.0",
  locale: "en",
  released_on: Date.new(2026, 3, 1),
  position: 1,
)

overview = IngenicDocPage.create!(
  version: previous,
  slug: "overview",
  title: "Overview",
  locale: "en",
  position: 0,
  body: <<~MD,
    ## Chip introduction

    The T32Pro series is a highly integrated vision SoC.

    | Item | Value |
    | --- | --- |
    | CPU | ... |
  MD
)

IngenicDocPage.create!(
  version: latest,
  parent: nil,
  slug: "quick-start",
  title: "Quick Start",
  locale: "en",
  position: 1,
  body: "How to build and flash your first image.",
)
```

### 版本继承

一个版本只保存"在本版本中编辑过的页面"。上面的 `overview` 是在 2.0.0 里写的，
2.1.0 里没有动过，但 2.1.0 仍然会显示它——解析器按版本从旧到新遍历，同一个 slug
以最新的一版定义为准。因此发布新版本不需要复制整套手册，也就不需要维护多份副本
保持同步。

顺序由 `position` 决定，数值小的在前。调整版本顺序会改变继承关系，这本身就是
机制的一部分：把某个版本排到 2.0.0 之后，它就什么都继承不到了。

如果一个页面存在于某个版本，而它的父页面只存在于更早的版本，它仍然会挂在那
个父页面下，所以在某个版本里单独覆盖一个页面不会让它脱离目录树。

### 地址规则

```text
/ingenic/docs/<系列>/<型号>/<版本>/<页面>
```

系列之后的每一段都可以省略。缺少的段落会解析为该层级下第一个已发布条目
（`position` 最小的那个），`latest` 是"被标记为 `latest: true` 的版本"的别名。
因此 `/ingenic/docs` 打开第一个系列的第一个型号，`/ingenic/docs/t-series`
打开 T 系列下的第一个型号。

注意第一段永远按"系列"解析。`/ingenic/docs/t32pro` 不会打开型号 `t32pro`，
它会去找同名系列，找不到，然后回退到第一个系列。要链接到型号请写
`/ingenic/docs/t-series/t32pro`。

页面可以关联到一个已有的论坛主题，设置 `topic_url` 即可：

```ruby
overview.update!(topic_url: "/t/getting-started-with-t32pro/123")
```

## 下载资源

资源分类是一张表而不是固定列表，可以在 **Ingenic → Downloads → Classifications**
中增删改名。迁移已经把这批分类写成数据行：`sdk`、`firmware`、`manual`、
`datasheet`、`toolchain`、`example`、`release_notes`、`other`。所以通常只需要
挑一个用，不需要新建。

```ruby
sdk = IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en")
```

一个资源要么指向存放在别处的文件，要么自己带一个上传的文件。指向外部文件时：

```ruby
IngenicDownload.create!(
  product_slug: "t32pro",
  category: sdk,
  version: "2.1.0",
  locale: "en",
  name: "T32Pro SDK 2.1.0",
  description: "Linux SDK including toolchain and examples.",
  platform: "Linux",
  architecture: "x86_64",
  access_level: "public_login",
  file_url: "https://download.ingenic.com/t32pro/sdk-2.1.0-en.tar.gz",
  file_size: "1.4 GB",
  file_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
  released_on: Date.new(2026, 9, 1),
)
```

`product_slug` 填产品树里型号的 slug。如果这个资源是整个系列共用的，填系列的
slug 也是可以的。

`access_level` 取三个值之一：`public_login`（登录即可）、`login_form`（登录，
并且已填写开发者信息）、`login_form_request`（登录、已填写开发者信息，并且申请
已通过审核）。默认值是 `public_login`。

无论级别是什么，`file_url` 都不会由列表接口发给浏览器——页面给出的是插件自己的
接口地址，由接口决定是否放行。凡是需要管控的文件，建议改用上传：放在对象存储上
的地址，任何拿到这个地址的人都能直接下载。

通过管理页面上传的文件会写到 `ingenic_download_storage_path`，并记录为
`storage_path` 和 `original_filename`。如果要在控制台里做同样的事，需要走控制器
用的那个辅助方法：

```ruby
stored = Ingenic::DownloadStorage.store(uploaded_file)
resource.update!(
  storage_path: stored[:path],
  original_filename: uploaded_file.original_filename,
  file_sha256: stored[:sha256],
  file_size: stored[:size],
  file_url: nil,
)
```

### 申请与授权

一次申请是 `ingenic_download_requests` 中的一行；批准它会签发一行
`ingenic_download_grants`。授权没有到期时间：申请通过后该账号可以一直下载这个
资源。真正说明"文件被取走"的是下载日志，而不是授权记录。

```ruby
request = IngenicDownloadRequest.create!(user: someone, download: resource)
request.approve!(admin, note: "welcome")

IngenicDownloadGrant.issue!(someone, resource, granted_by: admin)
IngenicDownloadGrant.find_by(user: someone, download: resource).revoke!(admin)
```

同样的操作在 **Ingenic → Downloads → Applications** 和 **Grants** 中都有，谁在什么
时候下载了什么记录在 **Ingenic → Downloads → Log**。

## 开发板

一块开发板属于产品树里的某一个型号，这正是目录能按系列和型号两级筛选的原因。
这个关联是可选的——开发板可以先列出、之后再挂到型号上——但把开发板挂到"系列"
而不是"型号"会被拒绝，因为那样它会在该系列的每个型号下都出现一次。

```ruby
IngenicBoard.create!(
  slug: "t32pro-evk",
  name: "T32Pro EVK",
  product: chip,
  locale: "en",
  description: "Evaluation kit for the T32Pro series.",
  specs: "2 GB DDR3 · dual Gigabit Ethernet · camera interface",
  image_url: "https://download.ingenic.com/boards/t32pro-evk.png",
  documentation_url: "/ingenic/docs/t-series/t32pro",
  application_url: "https://www.ingenic.com.cn/apply?board=t32pro-evk",
  purchase_url: "https://www.ingenic.com.cn/buy?board=t32pro-evk",
  position: 0,
)
```

`chip` 会从关联的产品自动填入，不需要手工设置；它仍然是一个字段，是为了支持
"开发板先上线、型号稍后再建"的情况。`application_url` 和 `purchase_url` 都是
站外链接，渲染时会带上 `rel="noopener noreferrer"` 并在新标签页打开。
`application_url` 必填，对应"申请"按钮；`purchase_url` 选填，对应 **Buy now**
按钮——不是每块板子都对外销售，只做申请发放的板子没有购买地址可填。

## 积分

积分是成员通过贡献获得的，也是下载资源可以标价消耗的。涉及三张表：
`ingenic_point_rules`（价目表）、`ingenic_point_entries`（流水账，每次变动一行，
只增不改）、`ingenic_point_balances`（每个账号的累计余额，由流水账推导得出，
也可以由流水账重新算出来）。

迁移会写入四条规则，这是插件的起点，不是必须保持不变的值：

| `event` | 积分 | 名称 |
| --- | ---: | --- |
| `topic_created` | 5 | Opening a discussion |
| `post_created` | 2 | Answering in one |
| `like_received` | 1 | A post of yours being liked |
| `solution_accepted` | 15 | Your answer being accepted |

"有哪些事件"是插件决定的——每个事件都需要 Discourse 里有地方会上报它——而分值、
名称和顺序是你们决定的。这四项都可以在 **Ingenic → Points** 页面修改，日常修改
建议在那里做，不必进控制台：

```ruby
IngenicPointRule.for(IngenicPointRule::SOLUTION_ACCEPTED).update!(points: 25)

# 停用一个动作但保留数据行：流水账里仍然会引用它。
IngenicPointRule.for(IngenicPointRule::LIKE_RECEIVED).update!(published: false)
```

`IngenicPointRule.amount_for(event)` 返回某个动作"当前"一次值多少分；对于已停用
或从未写入的规则返回 `0`。这正是停用一个动作之所以安全的原因。

### 流水账

没有任何地方需要手工写流水。每一次变动都经过 `Ingenic::Points`，它在同一个事务里
写入流水行并同步余额：

```ruby
Ingenic::Points.award(user: someone, event: IngenicPointRule::TOPIC_CREATED, subject: post)
Ingenic::Points.reverse(entry, reason: "the post went away", by: admin)
Ingenic::Points.reverse_subject(post, reason: "the post went away")
Ingenic::Points.spend(user: someone, points: 50, subject: resource, reason: "unlocked")
Ingenic::Points.adjust(user: someone, points: 25, note: "helped with a bug", by: admin)
Ingenic::Points.total_for(someone)          # 该账号的余额
Ingenic::Points.unlocked_download_ids(someone)
Ingenic::Points.rebuild!                    # 重新计算全部余额
```

一次奖励对同一个对象只记一次：奖励所对应的对象是唯一索引的一部分，所以同一个事件
第二次到达时不会重复发放，而是什么都不写。`award` 返回写入的流水行，或者在没有
任何东西需要记录时返回 `nil`——没有对应规则、规则分值为 0、积分功能已关闭、
或者这个对象已经发放过。`nil` 是正常结果，不是失败。

`spend` 用返回值表达结果而不是抛异常，因为调用方是一次下载，"积分不够"是一种需要
展示给用户的状态，而不是一个报错页面。返回值有三种：`:spent`（已扣分，资源归该
账号）、`:already`（之前已经买过，不再重复收费）、`:insufficient`（积分不足，
没有写入任何记录）。

流水行不会被修改。要撤回一次奖励，是再写一条方向相反的记录，因此流水账忠实反映
"发生过什么"——先发了分，之后又收了回来——而原来那条奖励记录仍然留在那里可以查看。

`ingenic_point_balances` 是一份缓存。如果它和流水账对不上——比如恢复备份之后，
或者有人直接改过数据库——执行 `Ingenic::Points.rebuild!` 就会把它算回来，并返回
修正了多少行。这也是"余额可以信任，但它不是权威"的原因。

### 资源标价

给资源标价就是在资源本身上设置一个字段。默认值 0 表示免费：

```ruby
resource.update!(point_cost: 50)
```

价格是在访问级别"之后"才询问的，而不是替代访问级别：一个标价 50 分、
级别为 `login_form_request` 的资源，对于新访客仍然是先登录、先填开发者信息、
先通过审核，然后才会提到积分。账号积分足够时列表显示 **Unlock for N points**，
不够时显示 **Needs N points**；购买会写入一条流水，所以同一个资源第二次下载
不再收费。

### 成员页面

`/ingenic/points` 向已登录成员显示自己的余额、价目表和自己的变动记录。这个页面
在前端是只读的，也不会显示其他人的记录。是否把它放进导航是主题的事情，不是插件
的事情：主题自带一个"积分"入口；如果站点已经配置了自己的 `ingenic_nav_items`，
需要自己补上这一项，因为一旦配置了列表，它会整体替换主题自带的默认列表。

## 增加第二种语言

每一行记录都带 `locale`。要为同一个产品增加中文文档，用 `locale: "zh_CN"` 建
对应的记录即可。接口会优先按访问者的界面语言匹配，匹配不到再回退到
`ingenic_default_locale`，所以只翻译了一部分产品也能正常显示。

语言代码必须使用 Discourse 自己的写法——`zh_CN`、`pt_BR`、`zh_TW`，不要写成
`zh-CN`。这个值会和 `I18n.locale` 比较，也就是访问者在 *偏好设置 → 界面语言*
中选择的语言，带连字符的代码匹配不上任何东西，那条记录就等于不存在。

页面可以按 slug 逐个翻译。当同一个 slug 同时存在 `en` 和 `zh_CN` 两行时，
以读者当前语言为准，翻译后的页面在目录中只出现一次；没有翻译的 slug 回退到
`ingenic_default_locale`。某个产品如果完全没有翻译记录，仍然会以默认语言打开。

产品、版本、页面、下载资源和开发板都遵循这套规则。产品树本身也是按语言分开的：
一个型号记录带着它名称所用的语言，因此"翻译过的型号"是同一个父级下的另一行记录，
而不是第一行记录的翻译字段。
