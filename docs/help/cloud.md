# Cloud storage

Connect Google Drive in **Settings → Cloud → Connect Google**, then approve access in the browser. Baker stores login tokens in macOS Keychain.

## Transfer captures

- Choose **Upload Latest Capture**, or **Drive** beside an image in Capture History.
- Choose **Refresh Drive** to list uploaded captures, then **Import** to save a local copy.
- Formula captures include their saved recognition result and edits.

Uploads create a **Baker** folder in Drive and a `.baker` metadata folder inside it. Changed images and formula metadata create new versions. Import preserves existing local formula edits.

Transfers run on request. Automatic synchronisation and general Drive browsing are outside this first integration. **Disconnect** removes the local login; uploaded files and the Google account grant remain.

## Connection setup

Under **Connection setup**, enter a Google OAuth **Desktop app** Client ID. If Google rejects the client credentials, choose **Import Desktop JSON…** and select the downloaded desktop credentials file. Keep that file private.

Enable Google Drive API in the same Google Cloud project. If the app remains in testing, add the signing-in account as a test user. See Google’s [credential setup](https://developers.google.com/workspace/guides/create-credentials).

Baker requests the app-file-limited `drive.file` scope. See [Google Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

If Google reports that Baker is testing and only developer-approved testers can connect, add the signing-in account under **Google Auth Platform → Audience → Test users**. Testing permits listed accounts; wider distribution requires the appropriate publishing configuration. See [Google audience settings](https://support.google.com/cloud/answer/15549945).

## Dropbox

Use an **App Folder** app. In [Dropbox App Console](https://www.dropbox.com/developers/apps), enable `files.metadata.read`, `files.content.read` and `files.content.write`. Under Settings → OAuth 2, register this exact redirect URI:

```text
http://127.0.0.1:53683/oauth/dropbox
```

Enter the public App Key in Baker’s **Cloud → Dropbox → Connection setup**, then choose **Connect Dropbox**. Login uses the browser and PKCE; Baker does not need an App Secret. This is a one-time app registration: individual users connect their own accounts through login. See [Dropbox OAuth](https://developers.dropbox.com/oauth-guide).

Choose **Upload Latest Capture**, or **Dropbox** in Capture History. **Refresh Dropbox → Import** saves a local copy. Files live under `Baker` within the app folder, with saved formula metadata in `.baker`. Each upload creates a new version; import preserves existing local formula edits. Transfers are manual, and Disconnect removes only the local login.
