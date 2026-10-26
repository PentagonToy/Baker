# OCR adapter template

Implement `formula` and/or `pdf` in `plugin.py` using a documented API or authorised local runtime. Update the manifest and list only implemented operations. The template returns failure until configured; it makes no network requests.

ZIP `plugin.json` and `plugin.py` together, then add the ZIP in Baker → Settings → Advanced → Plugin. Supply an optional API key through Baker’s Keychain-backed field rather than this package.

See [the complete protocol](https://pentagontoy.github.io/Baker/help/plugins/). Third-party plugins and services follow their own terms and privacy policies. Users and plugin authors must check permissions, costs and permitted use.
