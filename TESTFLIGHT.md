# Install Aula+ on your iPhone with TestFlight

GitHub builds and signs the app, uploads it to Apple, and your iPhone installs it from the TestFlight app.
You need a paid Apple Developer Program membership (99 USD/year). Your own internal test builds need no App Review.

## 1. Apple Developer Program (one time)

1. Go to https://developer.apple.com/programs/enroll and enroll as an **Individual** with your Apple ID.
2. Wait for the "Welcome to the Apple Developer Program" email.
3. Find your **Team ID**: https://developer.apple.com/account → scroll to **Membership details** → *Team ID* (10 characters, e.g. `AB12CD34EF`).

## 2. Register the app's IDs (one time)

Open https://developer.apple.com/account/resources/identifiers/list (Certificates, Identifiers & Profiles → **Identifiers**).

**App Group**
1. Click the blue **+** next to the "Identifiers" title.
2. Select **App Groups** → Continue.
3. Description: `Aula Plus`, Identifier: `group.com.majidkabir.aulaplus` → Continue → Register.

**App ID for the app**
1. Click **+** → **App IDs** → Continue → **App** → Continue.
2. Description: `Aula Plus`, Bundle ID: **Explicit** `com.majidkabir.aulaplus`.
3. In the Capabilities list tick **App Groups** → Continue → Register.
4. Open the new App ID again → next to App Groups click **Configure** (or **Edit**) → tick `group.com.majidkabir.aulaplus` → Continue → **Save**.

**App ID for the widget**
Same as above with Description `Aula Plus Widget` and Bundle ID `com.majidkabir.aulaplus.widget`, also with the same App Group.

Tip: the Identifiers list has a filter dropdown at the top right (**App IDs** / **App Groups**). If you can't see the group you made, switch it to **App Groups**.

## 3. Create the app in App Store Connect (one time)

1. Go to https://appstoreconnect.apple.com → **Apps** → blue **+** → **New App**.
2. Platform **iOS**, Name `Aula Plus` (any name that's free), Primary language Danish,
   Bundle ID: pick `Aula Plus - com.majidkabir.aulaplus`, SKU `aulaplus`, User access **Full Access** → **Create**.

If the Bundle ID list is empty, step 2 isn't done yet (or wait a few minutes and reload).

## 4. API key for GitHub (one time)

1. https://appstoreconnect.apple.com → **Users and Access** → tab **Integrations** → **App Store Connect API** (left).
2. **First time only:** you'll see **Request Access**. Click it, tick the checkbox, **Submit**. Apple has to approve this; it's usually quick, but can take a while.
3. When approved: tab **Team Keys** → **Generate API Key** (or **+**).
   Name `GitHub`, Access **Admin** → **Generate**.
   (Admin is needed so Xcode can create the signing certificate for you.)
4. Click **Download** next to the key and save the `AuthKey_XXXXXXXXXX.p8` file. **You can download it only once.**
5. Note the **Key ID** (in the table) and the **Issuer ID** (shown above the table, with a Copy button).

## 5. GitHub secrets (one time)

On your Mac, turn the key into one line of text and copy it:

```sh
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Then in https://github.com/majidkabir/aula-plus → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**, add four secrets:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_KEY_P8` | paste (the base64 text you copied) |
| `APPLE_TEAM_ID` | Team ID from step 1 |

## 6. Build and upload

GitHub → **Actions** → **TestFlight** (left) → **Run workflow** → **Run workflow**. It takes about 10–15 minutes.

## 7. Install on your iPhone

1. App Store Connect → your app → **TestFlight** tab. The build appears 5–20 minutes after the workflow finishes (status "Processing" first).
2. Left side, under **Internal Testing**, click **+** → name `Me` → add yourself as tester.
3. On the iPhone: install **TestFlight** from the App Store, sign in with the same Apple ID, open the invite email (or just open TestFlight) → **Install**.

Every new run of the workflow shows up as an update in TestFlight. A build stops working after 90 days, so run the workflow again before then.

## If the workflow fails

| Error | Fix |
|---|---|
| `Missing repository secret …` | Add that secret (step 5). |
| `ASC_KEY_P8 is not the base64 of the .p8 file` | Redo the `base64 … \| pbcopy` command and paste again. |
| `No profiles for 'com.majidkabir.aulaplus' were found` / certificate errors | The API key must have **Admin** access (step 4). |
| `… app group …` errors | Step 2: both App IDs need the App Group ticked and configured. |
| `No suitable application records were found` | Step 3 isn't done, or the Bundle ID there differs. |
| Upload says agreements are missing | App Store Connect → **Business** (or the banner at the top) → accept the latest agreement. |
