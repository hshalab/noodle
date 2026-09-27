# Changelog

## [Unreleased]

### Added

- Settings has a Companions tab to install, open and update Noodle Computer, Browser and Applet on the Hub's Mac. Its badge shows how many have an update.
- A plan can limit which models each harness it lends may use. Bots on a harness with limited models must use one of them.
- The first launch opens on a welcome, as Noodle's does, that ends in pairing your first device.
- Pair… in the menu bar menu opens a window to pair a new device, under the Noodle wordmark as on the welcome: choose one of the Hub's users or name a new one, then scan its QR code or share its link.
- When the Hub's Mac is on Tailscale, the Hub lists its Tailscale name among its addresses, so devices can reach it wherever they are on your tailnet.
- People can pair more of their own devices from Noodle on their phone. Can Pair, beside each user in Settings > Users, is on unless you turn it off.

### Changed

- Bots can no longer pop a noodlet window up on the Hub's screen. Their noodlets run out of sight.
- The Usage window keeps its bot, group, measure and period choices in the toolbar, with the period's dates under the title, totals in one strip above the chart and the breakdown in a table below it.
- Buttons in the rows of the Users, Plans and Bots settings look like links, as in System Settings.
- A device's Remove link in Settings > Users no longer ends in an ellipsis.
- Quitting the Hub, from its menu or with Command-Q, asks first and says how many people and devices are connected and how many bots are working. Logging out and shutting down are not held up.
- Restarting to install an update asks first in the same way.
- The menu bar menu groups Pair… and Usage apart from Settings…, and Usage no longer ends in “…”.

## [0.4.1] - 2026-09-27

### Changed

- What happens to phones' notifications goes to the system log, under the category Notifications, with any error from iCloud.

## [0.4.0] - 2026-09-27

### Added

- The Hub remembers how far each person has read their conversations, so reading on one device clears the unread dot on their others.
- Phones away from the Hub are notified of new replies.

## [0.3.2] - 2026-09-27

### Changed

- Opening the Hub yourself shows its Settings, so it no longer seems to do nothing. At login it still starts quietly in the menu bar.

### Added

- The menu bar icon shows a green dot while someone is connected to the Hub.

### Fixed

- Each picture's size is sent with it, so Noodle for iPhone keeps its place in a conversation while pictures load.
- Live views keep up on a slow or busy connection: video gets lighter to fit the link instead of arriving seconds late and stuttering.
- Settings, Usage and bot Activity windows open in front of other apps instead of behind them.
- Usage no longer counts a Claude bot’s earlier tokens and cost again each time the bot restarts. Usage recorded before this fix still includes the repeats.

## [0.3.1] - 2026-09-26

### Changed

- Send bot pictures and tool icons apart from their lists to the latest Noodle and Noodle for iPhone, which fetch each once, so lists stay small however many pictures they show. Editing a bot from a device keeps its picture without sending it back.

### Fixed

- Fix a crash when a tool connection fails while the Hub is listing or updating people's tools.

## [0.3.0] - 2026-09-26

### Added

- Reach the Hub away from home. Open Port on Router in Settings > Network asks the router, through UPnP or NAT-PMP, to forward the Hub's port and keeps it open; the router's public address joins the addresses invitations carry, and paired devices pick it up when they next connect. Network says when the router cannot, for example when it sits behind another router or your provider shares its address.
- React to your bots' messages from Noodle for iPhone, and see their reactions there as they happen. Paired devices also see what each bot is doing: working, ready, failed or offline.
- Keep the transcript of voice messages sent to the Hub's bots, so bots read what was said.
- Let the Hub's bots build and share noodlets with Noodle Applet on the Hub's Mac, as they do in Noodle. A noodlet opens live only for the owner of the bot whose folder it came from, however the bot links to it. Install Noodle Applet on the Hub's Mac to use them.
- Show what a bot's browser or computer card points at live to its owner in Noodle, and pass on their clicks, typing and scrolling.
- Run browsers for the Hub's bots in Noodle Browser on the Hub's Mac. People make and delete them from Noodle; each belongs to the person who made it and reaches only the bots they choose. Install Noodle Browser on the Hub's Mac to use them.
- Run computers for the Hub's bots in Noodle Computer on the Hub's Mac. People make and delete them from Noodle; each belongs to the person who made it and reaches only the bots they choose. Install Noodle Computer on the Hub's Mac to use them.
- Keep people's tool connections on the Hub. Each connection belongs to the person who added it from Noodle, reaches only the bots they choose, and keeps its sign-in in the Hub's Keychain, where bots never see it.

### Changed

- Refuse devices that are not paired before reading anything they send. An invitation's code carries a key made for it alone, and only a device holding that code can reach the Hub to join, once; the joining device also proves it holds the key it pairs. A removed device is disconnected at once. Devices join with the latest Noodle or Noodle for iPhone.
- Send conversations to devices a page at a time, newest first, with card pictures fetched separately, so a long conversation loads quickly and never fails for its size.
- A live view of a browser, computer or noodlet in a Noodle Browser, Computer or Applet too old to show it says which app to update.
- Stream live views as video, each picture as soon as it is ready and no larger than the viewer's window, skipping old pictures for a device that falls behind, and take the person's input on the same connection, in order. While someone watches a browser, computer or noodlet, its bot waits until they close the view. A view the Hub cannot open tells the device why.
- Send links to the browsers, computers and noodlets the Hub's bots share as links with their pictures, so devices open them live. Cards the Hub saved earlier become links when it starts.

### Removed

- The Hub's bots no longer call tools on their owner's Mac. Update Noodle on paired Macs along with the Hub.

### Fixed

- Opening the app again brings the copy already running to the front instead of starting a second one on the same data, however it is started.
- Delete a removed tool connection's sign-in from Keychain even when the first try fails. The Hub tries again until it is gone.

## [0.2.0] - 2026-09-25

### Added

- See token use and cost for the Hub's bots by bot, harness or model from Usage… in the menu bar, with the same view as Noodle.
- Add users in Settings > Users and choose which harnesses and profiles they can use with plans in Settings > Plans, where each plan lists what it lends and Edit… switches its harnesses on or off. New users start on the Default plan, which lends nothing until you add to it.
- Pair a Mac running Noodle with the Hub. Invite… next to a user in Settings > Users shows a QR code and a link to copy or share by AirDrop; opening it in Noodle joins the Hub as that user. The device then appears under the user, who can remove it. Each device proves itself with its own key over an encrypted QUIC connection, and invitations work once and expire after 15 minutes.
- See whether the Hub is reachable in Settings > Network: its port and the addresses invitations carry. Add Address records a domain, public address or forwarded port that reaches the Hub from outside your network.
- See who is connected: Settings > Users marks each device that checked in during the last 90 seconds, and Settings > Network counts the people and devices connected now.
- Run the bots people keep on the Hub from Noodle. Each belongs to the user who made it, runs on a harness their plan lends, and talks only with that user; the plan is checked when the bot is made and before every message. Replies reach the user's devices as they are written. Removing a user removes their bots.
- Let the Hub's bots use the tools their owner's Mac lends them. Each call is passed to that Mac, which runs it within what it assigned to the bot; while the Mac is away the bot is told its tools are unavailable.
- See every bot on the Hub in Settings > Bots, with its owner, harness and status, and open its folder or its activity.
- Get Noodle Hub from the Noodle Suite installer, the download table and the website, alongside Noodle's other companions.

### Changed

- Show only Harness, Users, Plans, Bots, Network and Update in Settings for now. Heartbeat, Sandbox, Tools and Companions return when the Hub runs shared agents.

## [0.1.0] - 2026-09-24

### Added

- Try an early development build of Noodle Hub. It does not run bots yet.
- Run Noodle Hub from the menu bar, keeping its bots and data apart from Noodle's. Its Settings cover harnesses, heartbeats, the sandbox, tools, companions and updates, with the same controls as Noodle.
- Check for updates in Settings > Update. Released builds also check once a day.
