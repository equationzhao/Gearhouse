# Gearhouse

[English](README.md)

用于管理骑行装备、组件磨损和保养记录的原生 iPhone App。直接从 [Intervals.icu](https://intervals.icu/) 同步活动，无需自建服务器。

## 功能

- 树形装备结构：自行车 → 轮组 → 轮胎、碟片和飞轮。
- 记录装配日期和组件换车，按历史归属统计使用量，重算前预览变化。
- 库存管理，同类别同名的装备合并显示数量，各自保留里程和历史。
- 按装备类别设置是否计入骑行台和虚拟骑行距离。
- 记录保养、摔车、滴蜡和煮蜡，设置里程或日期提醒。
- 查看装备活动记录、日期范围统计和组件时间线。
- 保存图片、发票、说明书和保修凭证。
- 自动备份到选定的 iCloud Drive 文件夹，恢复历史版本。

当前为单设备应用，界面为简体中文。iCloud Drive 用于备份与恢复，不提供多设备实时同步。活动同步和备份的后台执行时机由 iOS 决定。

## 本地构建

需要 Mac、Xcode 和 Python 3。项目已使用 Xcode 27.1 验证，App 支持 iOS 17 及以上。图标使用 Icon Composer 的 `.icon` 格式，建议使用 Xcode 26 或更新版本。只有重新生成演示数据时才需要 Node.js。

```sh
python3 scripts/bundle-rules.py
python3 scripts/generate-project.py
swift test
open GearhouseApp.xcodeproj
```

真机运行前，将 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig`，填写自己的开发团队及唯一 Bundle ID。这个本地配置不会提交到 Git。连接并信任 iPhone、打开开发者模式，然后在 Xcode 中选择 `GearhouseApp` 和目标设备运行。

在 App 的“同步 → Intervals.icu 连接”中输入个人 API Key，可从 [Intervals.icu 设置](https://intervals.icu/settings)获取。密钥存入 Keychain，不进入备份。

不连接账户也能体验：在 Debug 构建的启动参数中添加 `-preview-route tree`。演示数据、凭据存储与正式数据隔离。

## 开发与文档

- [完整使用说明](docs/user-guide.zh-CN.md)
- [构建、测试与项目生成](docs/development.md)
- [代码结构与数据流](docs/architecture.md)
- [隐私与数据](docs/privacy.md)
- [贡献指南](CONTRIBUTING.md)

当前源码集中在本仓库，构建不依赖归档网页版。SwiftUI 提供界面，JavaScriptCore 在进程内执行业务规则，不需要 Node.js 服务。

## 许可证

采用 [MIT License](LICENSE)：允许使用、修改、商用和再分发，需保留版权及许可声明。平台与资源说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

Gearhouse 是独立项目，与 Intervals.icu 及示例中的装备品牌无隶属关系。
