# Website and OAuth setup

The public site is built from this repository and hosted by GitHub Pages. Its privacy contact is [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com).

## Public addresses

| Google Branding field | Value |
| --- | --- |
| Application home page | `https://pentagontoy.github.io/Baker/` |
| Application privacy policy link | `https://pentagontoy.github.io/Baker/legal/privacy.html` |
| Application Terms of Service link | Leave empty for this preview |
| Authorised domain candidate | `pentagontoy.github.io` — no scheme, path or trailing slash |

Confirm that the first two addresses load without login before submitting them. The home page links to the privacy policy. The policy describes the current app, not planned services.

## Ownership and verification

GitHub Pages hosting does not complete Google's brand verification. Google's current [domain verification guidance](https://support.google.com/cloud/answer/13804266?hl=en) requires a DNS-verified Domain property in Search Console, using the Google Cloud project's owner account. A URL-prefix HTML verification alone does not satisfy that guidance.

For public OAuth verification, connect a domain whose DNS you control to GitHub Pages. Add its Domain property in Search Console, publish Google's TXT record in DNS and verify ownership. Update the home page, privacy URL and authorised domain together. After verification, allow the 24 hours requested by the Branding console before requesting reverification. Changing `/Baker/` to `/Baker/index.html` does not verify ownership.

No domain or verification token is invented in this repository. The current GitHub Pages addresses remain usable for documentation while domain ownership is unresolved.

Testing access and brand verification are separate. While the OAuth project is in Testing, add the signing-in accounts under Audience → Test users. A live website alone does not lift that restriction. See [Google audience settings](https://support.google.com/cloud/answer/15549945).

## Build and publish

The site uses Zensical’s modern theme and follows the guide/help structure used by the other Nordic projects, with a separate legal section. Shared artwork is staged from `others/assests` by `tools/docs/build.py`; source Markdown remains usable in GitHub.

The documentation workflow builds and deploys after relevant changes reach `main`. GitHub Pages must use **GitHub Actions** as its source. A local build needs the pinned `requirements-docs.txt` packages and fresh staging/output directories outside the checkout:

```sh
python tools/docs/build.py --workspace /path/to/fresh-staging --site-dir /path/to/site
```

The app's six OCR languages are independent of website language. The documentation and privacy policy are currently written in English.
