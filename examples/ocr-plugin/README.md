# OCR adapter template

Implement `formula` and/or `pdf` in `plugin.py` using a documented API or authorised local runtime. Update the manifest and list only implemented operations. The template returns failure until configured; it makes no network requests.

ZIP `plugin.json`, `plugin.py` and any helper files together, then add the ZIP in Baker → Settings → Advanced → Plugin. For interactive setup, implement the configure operation and add `"configuration": true` to the manifest; Baker then shows Configure… instead of a key field. Keep the setup process in the foreground and return one JSON response when finished. Supply an optional API key through Baker’s Keychain-backed field rather than this package.

See [the complete protocol](https://pentagontoy.github.io/Baker/help/plugins/). Third-party plugins and services follow their own terms and privacy policies. Users and plugin authors must check permissions, costs and permitted use.

## Login popup

`setup.py` provides a compact email/password form, a foreground loopback server and Baker’s in-app window hand-off using only Python’s standard library. Implement `authenticate(email, password)` using your authorised service, and a store object with `save(session)` to persist the returned session securely. Import the adjacent helper with `importlib.util.spec_from_file_location`, then return `setup.run(store, authenticate, announce=False)` from `configure`. Set `"configuration": true` in the manifest and include `setup.py` in your ZIP. Never print or package credentials; Baker expects only the final JSON response on stdout.

The form marks username and current-password fields for AutoFill. A local page does not share a service website’s identity, so existing website passwords are not guaranteed to appear automatically. Baker’s Passwords… button opens Apple Passwords for manual selection; Baker does not read its contents. Services that require OAuth or SSO should supply their own authorised authentication flow instead of this password-form example.
