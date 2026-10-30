# DFRadar（iOS 端）

PC 端把「自己坐标 + yaw + 实体列表」用 UDP 推过来，这个 App 用 W2S 投影渲染
**人形骨架 + 血条 + 距离 + 墙后标记**，并通过 **Picture-in-Picture 浮窗**浮在游戏上方。

不注入、不越狱、不录屏、不用 VPN。

## 通信契约

```
UDP 47810，每报文一个 JSON，UTF-8，20~30Hz
{"self":[x,y,z],"yaw":deg,"pitch":deg,"hfov":deg,"ents":[[id,x,y,z,hp,visible],...]}
坐标米 / Z 向上 / yaw 0=+X 逆时针为正 / hp 0~100(-1 未知) / visible 1 可见 0 墙后
```

## 目录

```
project.yml                  xcodegen 工程定义
Resources/Info.plist         UIBackgroundModes=audio（PiP 必需）
Sources/Projection.swift     V3 + w2s()          ← 与 PC 端同一套数学
Sources/Net.swift            Msg + UDP 收包
Sources/Renderer.swift       17 点人形骨架 + 血条 + 距离 + 墙后虚线
Sources/Support.swift        UIImage→CVPixelBuffer→CMSampleBuffer + 静音保活
Sources/PiPHost.swift        AVSampleBufferDisplayLayer + PiP
Sources/MockWorld.swift      假数据（不接 PC 也能看效果）
Sources/AppMain.swift        AppDelegate + RadarVC
.github/workflows/build.yml  无 Mac 出 ipa
```

## 出包（不需要 Mac）

1. 推到 GitHub 私有仓库（**注意：私有**，这是唯一提醒）
2. Actions 里跑 `build`，下载 artifact `DFRadar-ipa`
3. Windows 上 Sideloadly + 自己的 Apple ID 签名装上（免费账号 7 天到期，重签一次即可，App 数据不清）
4. 手机「设置 → 通用 → VPN与设备管理」信任该开发者
5. 手机「设置 → 通用 → 后台 App 刷新」对该 App 打开

## 用法

1. 手机和 PC 连同一个 Wi-Fi（或 PC 的移动热点）
2. PC：`python neta.py mock --phone <手机IP>` 先验证显示链
3. 打开 App → 点「自测（假数据）」→ 预览里应出现 5 个骨架，第 2 个是红色虚线 + “墙后”
4. 点「启动 PiP」→ 回到桌面 → 打开游戏 → 浮窗出现，可拖动、可捏合放大到约屏宽 88%
5. 浮窗里显示的是雷达/投影视图本身（不透明），**不是叠在游戏画面上的半透明层**——放在角落，抬眼扫

## 三条待真机验证（Windows 上无法确认）

App 里有「环境自检」按钮，点一下直接读实测值：

| 输出项 | 期望值 | 期望值不符时怎么办 |
|---|---|---|
| `captured` | `false` | 本方案不开 ReplayKit，若为 TRUE 说明系统仍认为在录屏 → 关掉其它录屏/直播 App |
| `screens` | `1` | 为 2 说明接了外接屏/投屏，游戏侧可查 |
| `otherAudio` | `false` | 为 TRUE 说明静音保活被发现 → 把 `.playback` 改 `.ambient`（iOS 可能弱化保活，需权衡） |
| `route` | `Speaker` 或 `Headphones` | 出现 `HDMI`/`AirPlay` 会暴露采集意图 |
| `category` | `playback/default` | 开播后若变成 `record` 类，说明别处抢了会话 |

其余两项：

1. **PiP 能否在游戏前台持续显示**：依赖后台音频会话。若 1~2 分钟后浮窗自动消失，说明保活失败
2. **`UIScreen.isCaptured` / `AVAudioSession.isOtherAudioPlaying`** 是否被游戏用于判定：只能靠“开/关各打 10 局对比行为”，见根目录 README 的判定协议

## 轴序排错

骨架位置左右反了 / 上下反了 → 改 `Projection.swift` 顶部注释里的 Unity 系配方（X 右 / Y 上 / Z 前）。
前后反了 → 把 `r` 的符号取反（`V3(x: sin(y), y: -cos(y), z: 0)`）。
