# QuietPhone 0.1.2

为实体静音键损坏的 iPhone 提供软件静音：同时保持铃声静音和媒体音量为零，覆盖使用普通媒体输出的视频、音乐和游戏。

提供 Rootful（有根）和 Rootless（无根）两个独立安装包，均包含 arm64 / arm64e。Rootful 面向 iOS 14 及以上的有根越狱环境；Rootless 面向 Dopamine / iOS 15/16。已在 Rootless iPhone X / iOS 16.1.1 上完成安装及静音验证；Rootful 尚未经过真机验证，其他机型和系统也需实测。

## 使用

1. 按越狱类型添加软件源，搜索 **QuietPhone** 安装：有根使用 `https://wwangmc.github.io/repo/`，无根使用 `https://wwangmc.github.io/repo/rootless/`。也可从 [Releases](https://github.com/wwangmc/QuietPhone/releases) 下载对应的 `.deb`：`iphoneos-arm` 为有根包，`iphoneos-arm64` 为无根包。依赖 PreferenceLoader 和越狱注入框架。
2. **安装后重启 SpringBoard 即默认静音，无需另开开关。** 如需恢复声音，在“设置 → QuietPhone 软件静音”关闭“铃声和媒体静音”，切换即时生效。已有明确保存的关闭设置会保留，可在设置中重新开启。
3. 关闭时恢复之前保存的铃声状态；媒体音量仅在能够识别当前输出设备并有对应快照时恢复，否则保持当前音量，由用户手动调整。
4. 卸载前先关闭开关并确认音量恢复。插件不运行时不能执行恢复操作；安全模式、卸载或退出越狱后不能继续保持静音。

## 实现与边界

- 0.1.2 增加 Rootful iOS 14+ 安装包；两种包使用同一份静音和设置代码，只在部署目标、依赖和安装前缀上区分。
- 0.1.1 起，没有保存启用配置时默认为开启；设置面板显示与实际行为一致。0.1.0 默认为关闭，可能导致安装后仍然有声音。
- 0.1.1 同时修正 PreferenceLoader 的控制器声明和设置列表结构，使设置入口能够加载。

- 只注入 SpringBoard，不注入每个游戏，也不改写游戏文件。
- 经 `SBRingerControl` 设置系统铃声静音，拦截同进程的解除静音请求，以处理实体键误触发。
- 经 `AVSystemController` 将 `Audio/Video` 类别音量设为零，并拦截 SpringBoard 经此接口发起的调高请求。
- 监听系统音量及输出路由变化。其他进程调高媒体音量后重新设零，启用时另有两秒间隔的兜底检查。
- 因为跨进程请求采用事件响应纠正，**不能保证音量变化、路由切换时绝无瞬间出声**。蓝牙、AirPlay、独立音量的外设及特殊音频会话均需实测。本版不是在音频混音器中丢弃所有采样的绝对静音方案。
- 原音量按系统输出路由标识分别保存，并在 respring 后继续使用；关闭后清除此次静音的快照，不会在以后连接其他设备时突然恢复音量。
- 不单独修改 Alarm / PhoneCall 类别，不保证屏蔽闹钟、通话或紧急提醒；没有关闭震动。
- 使用私有接口且做了运行时 selector 检查。接口不存在时跳过对应能力，不强行调用；这不能替代真机验证。

参考接口声明：[Theos AVSystemController](https://github.com/theos/headers/blob/master/Celestial/AVSystemController.h)。

## 构建

在已安装 Xcode、Theos、GNU make、ldid、xz 和补丁版 iPhoneOS16.5 SDK 的 macOS 上：

```sh
export THEOS=/path/to/theos
gmake TYPE=1 clean
gmake TYPE=1 FINALPACKAGE=1 package
```

`TYPE=0` 编译 Rootful，`TYPE=1` 编译 Rootless，默认为 `1`。切换模式前用相同 TYPE 执行 clean。RootHide 不在本项目的构建范围内。

| 类型 | 参数 | 最低部署版本 | 安装前缀 | 包架构 |
| --- | --- | --- | --- | --- |
| Rootful 有根 | `TYPE=0` | iOS 14.0 | `/` | `iphoneos-arm` |
| Rootless 无根 | `TYPE=1` | iOS 15.0 | `/var/jb` | `iphoneos-arm64` |

两种包的二进制都包含 arm64 / arm64e。iOS 14 的部署下限适用于现代 arm64e ABI，不支持 iOS 13 及更早版本。

也提供 `.github/workflows/build.yml`：项目位于 GitHub 仓库根目录时，推送 main/master、提交 PR 或手动运行 **Actions → Build Theos packages** 可以构建。在成功运行的 **Artifacts → QuietPhone-rootfull / QuietPhone-rootless** 中下载对应 `.deb`；构建日志为 `build-log-<模式>`。`rootfull` 是构建矩阵沿用的拼写，表示 Rootful。

0.1.0 已完成 [Actions 编译](https://github.com/wwangmc/QuietPhone/actions/runs/40992688050)，源码提交为 `c4b9caea48712358634a66d950b13591b6af99fa`。安装包为 `com.example.quietphone_0.1.0_iphoneos-arm64.deb`，SHA256 为 `66122b12ce8ea8088d84c7905fd56063d1374bc8210aba4b469c9f4d49a98ef6`。发布使用同一份经过校验和真机测试的安装包；后续许可证和说明更新没有改变插件代码。

0.1.1 已通过 [Actions 编译](https://github.com/wwangmc/QuietPhone/actions/runs/40995663430)，源码提交为 `32cd61d285d07d3f985c96fea0f9ee229fc33f9f`。安装包为 `com.example.quietphone_0.1.1_iphoneos-arm64.deb`，SHA256 为 `82366fa07071a78334709bc655e633e25ec3c5b600c02bf36335daa08a18db6e`。

## 验证范围

本地通过 plist、YAML、元数据和打包路径检查；Actions 通过 Logos 预处理、arm64 / arm64e 编译链接及 Rootless deb 打包。安装包校验后经 MKS 安装到 iPhone X / iOS 16.1.1，dpkg 安装成功，SpringBoard 重载后启用插件。

2026-10-30：启动 `com.korea.mrtgd2.ios` 并确认游戏在前台；用户现场反馈“没有声音了”。这验证了该设备和该游戏当时的静音效果。其他游戏、视频、蓝牙、AirPlay、音量恢复、长时间运行和其他 iOS 版本尚未实测。

同日，在另一台原先报告无效的 iPhone X / iOS 16.1.1 上升级 0.1.1：没有预先写入启用配置，重载后自动保存原始扬声器音量和铃声状态，设置面板正常显示且默认开关为开启。用户确认“好了它生效了 我看到了”。其他机型和系统仍需验证，手动关闭及音量恢复流程尚未完成真机确认。

这台设备的插件偏好实际位于 `/var/jb/var/mobile/Library/Preferences/`，手动配置时需按设备实际路径核对；日常使用优先通过设置面板切换。

真机验收应覆盖：启用后播放视频/游戏、按键和控制中心调音量、坏键抖动、锁屏解锁、respring、蓝牙连接/断开、关闭后恢复音量、再次启用与卸载。先在一台设备上验证后再用于其他手机。

## 开源

源码仓库：[wwangmc/QuietPhone](https://github.com/wwangmc/QuietPhone)。本项目采用 [MIT 许可证](LICENSE)，允许使用、修改及再分发，须保留许可证和版权声明。
