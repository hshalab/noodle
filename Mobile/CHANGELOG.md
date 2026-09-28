# Changelog

## [Unreleased]

### What to Test

- Pull down on the bots list and type in Search: only bots whose name, description or conversation match are listed, in one list without the pinned circles. Accents and capitals do not matter.
- Touch and hold a bot in the list: a menu offers Pin and Edit Bot…. On a pinned circle it offers Unpin and Edit Bot….
- In a conversation, tap the … button at the top right: New Session asks first, then starts the bot with a fresh context. When the bot has failed, Kick is there too and starts it again, asking first when the Mac or Hub would. Try it with a bot on your Mac and one on a Noodle Hub.
- With a phone paired to a Mac, create or edit a bot: Harness lists the harnesses installed on the Mac and their profiles, by name, and Model lists all of the chosen harness's models. Needs the Mac on the next Noodle update.
- Paired with a Mac serving your devices (Settings > Hub in Noodle): create a computer and a browser, add a tool and sign it in, then give them to a bot. They appear in Noodle on the Mac too, and the bot can use them.
- Open a conversation: the Message field and the + beside it are as tall as Search on the bots list.

### Added

- Search the bots list by name, description or what was said, as on the Mac.
- Touching and holding a bot shows a menu with Pin or Unpin and Edit Bot….
- Kick and New Session, in a conversation's … menu, start a stuck bot again or give it a fresh context, as on the Mac.
- New Tool lists the services your Hub offers, with search, and adds the one you tap and signs it in. Your own MCP server is under Custom MCP Server at the end of the list.

### Fixed

- The Message field in a conversation is as tall as Search on the bots list.
- Noodle Hub is tried again for a few seconds when it is starting up or the network is settling, instead of failing at once.
- A bot's harness shows its name rather than its internal identifier when the Hub no longer lends it under the same profile.
- Switching a new computer between Shell and Desktop changes its name to match, unless you typed your own.
- On a Mac serving your devices, creating or changing tools, computers and browsers no longer fails with "Manage tools, computers and browsers in Noodle on the Mac." The phone works on the Mac's own ones.

## [0.5.0] - 2026-09-28

### What to Test

- Open a conversation: its latest message sits just above the message field, with no gap under it, and the conversation does not sit shifted to the side before you first scroll.
- The app icon on the Home Screen is Apple's system blue, matching the Mac apps.
- Swipe right on a bot and tap Pin: it moves to a circle above the list, as in Messages. Tap the circle to open the chat; touch and hold it to unpin.
- Touch and hold a message: as in Messages, the conversation blurs, the message lifts, reactions float above it and Copy below. Tap a reaction to add or take it back, or tap outside to close. Try messages near the top and bottom of the screen, and a long one.

### Changed

- The app icon uses Apple's system blue, the same flat blue as the Noodle Mac apps.
- Touching and holding a message lifts it with reactions above and actions below, as in Messages.

### Fixed

- A conversation no longer opens scrolled past its end and slightly to the side.

## [0.4.0] - 2026-09-28

### What to Test

- Open an invitation link on the phone: it asks Join this Hub? with the Hub's key before joining. Compare the key with the one under the invitation on the Hub; Cancel joins nothing.
- In a Hub's profile, Hub Key matches the key under its invitations.
- Create or edit a bot: after choosing a harness, choose its model. With a plan that limits models, only those are offered.
- In your profile, tap Pair Another Device: scan its QR code with another phone or iPad, or copy or share the link. Once it expires, tap New Invitation.
- On the Hub, in Settings > Users, turn off Can Pair for your user: Pair Another Device no longer shows after you pull to refresh your profile.
- In Tools, sign a connection in: its sign-in page still opens and the connection signs in.

### Added

- Choosing a bot's model from those your plan on the Hub allows.
- Pair Another Device, in your profile, shows an invitation for another of your devices to join your Hub, when the Hub allows it.

### Security

- A Noodle Hub can no longer show a sign-in page on its own. The app shows one only for a sign-in you started, and only if it is a web page.
- An invitation link opened on the phone, from a web page, message or the Camera app, asks before joining and shows the Hub's key. Scanning or pasting an invitation in Noodle still joins straight away.
- A Hub's profile and Pair Another Device show the Hub's key.

## [0.3.2] - 2026-09-27

### What to Test

- Tap a notification of a new reply: the app opens that conversation.

### Fixed

- Tapping a notification no longer closes the app.

## [0.3.1] - 2026-09-27

### What to Test

- Leave the app and have a bot reply: a notification arrives with the bot's name and its reply.

### Fixed

- Setting up notifications waits until the phone is registered for push, which CloudKit needs before it notifies it; before, CloudKit refused them.

## [0.3.0] - 2026-09-27

### What to Test

- Record a voice message and tap the cross to discard it, including just beside it.
- Open a shared browser, computer or noodlet and rotate the phone both ways: it stays open.
- Open a picture in a message with several files and swipe to the others.
- Read a conversation on your Mac: its unread dot on the phone goes away. Read one on the phone: it clears on your Mac.
- Pair a second phone or iPad: conversations you already read elsewhere are not unread there.
- Allow notifications, then leave the app and have a bot reply: a notification arrives with the bot's name and its reply, and tapping it opens the conversation. Several replies in a row leave one notification.
- With the app open, no notification arrives. Reading the conversation removes its notification.

### Added

- Notifications of new replies while the app is closed or in the background, with the bot's name and what it said. This needs a Hub from this release on.

### Changed

- Opening a picture or file from a message lets you swipe through the message's other files.
- Conversations you read on another device are read here too, and reading here clears them on your other devices. This needs a Hub from this release on.

### Fixed

- Tapping beside the discard button while recording no longer opens the picture or message behind it.
- The live bars scroll smoothly while recording instead of stuttering.
- Rotating the phone no longer closes a shared browser, computer or noodlet you are watching.

## [0.2.2] - 2026-09-27

### What to Test

- Tap the plus by the message field and send a photo, a file or a camera shot from the panel.
- Record and send a voice message.
- Open a conversation with many pictures: it should not jump while they load.
- Send a message, and scroll up while a bot replies: you stay where you are.

### Changed

- The message field is taller, as in Messages, and holds the microphone and send button. The plus opens a panel with Camera, Photos and Files that grows out of it.

### Fixed

- A conversation no longer jumps while pictures load: each keeps the room it needs from the start, on Hubs that send the picture's size.
- Sending a message scrolls the conversation down to it. At the bottom, a new reply scrolls into view from its first line; scrolled up to read, you stay where you are.
- Recording a voice message no longer closes the app.

## [0.2.1] - 2026-09-26

### What to Test

- Join a Hub whose bots have photo pictures: chats show at once and the pictures follow.
- Rename a bot that has a picture; the picture stays.
- Open the app to see the swirl write Noodle before Pair.

### Changed

- Noodle opens with a swirl that rises from the bottom of the screen and writes its name, then shows Pair.

### Fixed

- Connect to a Hub whose bot list or live views are large, such as bots with photo pictures, instead of stopping at “The message is too large.” Chats show at once and bot pictures follow, each fetched once and kept; editing a bot no longer sends its picture back.

## [0.2.0] - 2026-09-26

### What to Test

- You need an invitation to a Noodle Hub. Join it by scanning its QR code, pasting its link or opening the link on the phone.
- Chat with your bots: send messages, photos, files and voice messages, and react to replies.
- Make a bot with New Bot, then change its picture, background, tools, computers and browsers in its settings.
- Tap a browser, computer or noodlet a bot shares to use it live.
- Join a second Hub from Profiles and switch between them, or show them all together.

### Added

- Open a browser tab, computer or noodlet a bot shared: tap its card to see it live on the Hub's Mac, tap to click, drag to scroll, and type with the keyboard button. Turn the phone sideways to give it the whole screen. Its bot waits while you have it open. Cards show the latest picture of a noodlet and the latest lines of a computer's terminal.
- Give a bot tools, computers and browsers from its settings. Tools, Computers and Browsers list yours on the Hub; tap one to let the bot use it or not, + adds one, and swiping deletes it. A tool that needs signing in opens its sign-in page on the phone.
- Join your Noodle Hub from an invitation: scan its QR code, paste its link, choose a photo of the QR code, or open the link. Noodle then shows who you joined as, your plan and whether the Hub is connected, and can leave the Hub.
- Chat with your bots on the Hub. They are listed like Messages, newest conversation first; tap one to read the conversation and send messages, and replies appear as the bot writes them. The app opens on what it last saw, including the harnesses your plan lends, and catches up with the Hub in the background.
- Make bots on the Hub with New Bot in the … menu, choosing a name, a colour and one of the harnesses your plan lends. Tap a bot's picture at the top of its chat to edit or delete it. Profiles in the same menu lists every Hub you joined: tap one to show its bots, open its details to see who you joined as or leave it, or add another Hub with Add Hub. With Show All Hubs Together, the bots of every Hub share one list, each marked with its Hub, and New Bot asks which Hub to make it on.
- Send photos, videos, camera shots and files with the + button next to the message field. Pictures show in the conversation, other files as cards that open in Quick Look, and web links show a preview. Your latest message says whether it was sent and delivered.
- See which bots replied since you last opened their conversation: a blue dot marks them in the list.
- Long replies fold after eight lines with Read more. Unsent text stays in each conversation, and a copied image can be pasted into the message field.
- React to a message by touching and holding it, with the same twelve reactions as on the Mac. Reactions show under the message with a count, and tapping one adds or takes back yours. A dot on each bot's picture shows whether it is working, ready or failed, as on the Mac.
- Send voice messages with the microphone next to the message field. Speech is transcribed on the device as you talk, and the bot gets the transcript with the audio. Voice messages play in the conversation with their waveform; touch and hold one to read its transcript.
- Type @ and part of a bot's name to pick it from a strip above the message field, as on the Mac.
- Give each conversation a background in the bot's settings: one of the Mac's four presets, a photo, or an image made with Image Playground. Touch and hold a picture in a conversation to use it as the background. Backgrounds stay on this phone.
- Edit a bot's picture as on the Mac: a photo or Image Playground image, or one of the Mac's symbols on a colour.
- Pin bots to the top of the list by swiping right. Pins stay on this phone.

### Fixed

- The join sheet no longer repeats its heading.
- The unread dot in the list of bots sits evenly between the screen edge and the bot's picture instead of against it.

### Changed

- Conversations open on their newest messages and load earlier ones as you scroll back; card pictures fill in as they come into view.

## [0.1.0] - 2026-09-25

### Added

- Try an early placeholder of Noodle for iPhone and iPad. It shows the Noodle symbol and does nothing else yet.
