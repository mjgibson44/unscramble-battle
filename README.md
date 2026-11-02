# Unscramble Battle

An iPhone word game written in SwiftUI. You get a scrambled word of 5 to 8 letters and tap the letters into the right order.

## Modes

- **Party (2–6 players):** each player uses their own iPhone, and the phones need to be close together. One person hosts and the others join. Phones find each other over Wi-Fi and Bluetooth, so no internet or accounts are needed. Everyone gets the same scramble at the same moment. Points depend on the order you finish: **1st gets 5, 2nd gets 3, 3rd gets 2, 4th gets 1**, and 5th, 6th or not solving it scores nothing. A round ends when everyone has solved the word or after 45 seconds. The host picks 1–10 rounds, and the highest total wins.
- **Face-Off (2 players, one phone):** lay the phone flat between you. The top half is upside down. The first to solve each word gets a point, and the first to reach the target (1–10) wins.
- **Solo Sprint:** ten words. Each word starts at 100 points per letter and drains the longer you take. Your best score is saved on the phone.

Tap a letter to put it in the next slot, and tap a filled slot to take a letter back. When every slot is filled, the answer is checked. Any real word that uses all the letters counts.

## Building it

You need a Mac with **Xcode 16 or later**. The app runs on iOS 16 and later.

1. Open `UnscrambleBattle.xcodeproj`.
2. Select the **UnscrambleBattle** target, then **Signing & Capabilities**, and choose your Team. A free Apple ID works for putting it on your own phone. If Xcode says the bundle identifier is taken, change `com.mjgibson44.UnscrambleBattle` to something unique.
3. Plug in your iPhone, select it as the run destination, and press Run.
4. To test Party, install the app on at least two iPhones. The first time you host or join, iOS asks for Local Network permission. Tap **Allow**.

The iOS Simulator can run Solo and Face-Off. For Party mode, use real phones.

## Code layout

- `UnscrambleBattle/Core`: the word list, the letter board, theme and shared helpers
- `UnscrambleBattle/Modes`: menu, Solo, Face-Off
- `UnscrambleBattle/Party`: networking (MultipeerConnectivity) and the Party screens
