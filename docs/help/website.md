# Website and ownership

The public documentation is hosted at [pentagontoy.github.io/Baker](https://pentagontoy.github.io/Baker/). The [privacy policy](../legal/privacy.md) uses [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com) as its contact.

Baker uses a save folder available in Finder and has no cloud-account login.

## Search Console ownership

The site retains the owner-supplied verification meta tag and [HTML verification file](https://pentagontoy.github.io/Baker/google835ba3f2038c2db2.html). The file is copied unchanged from `docs/google835ba3f2038c2db2.html`; the meta value comes from `extra.google_site_verification` in `mkdocs.yml` and is inserted into the initial home-page HTML by `tools/docs/build.py`.

After deployment, check the public file or page source and choose **Verify** for the matching method in Search Console. Keep both verification assets. Publishing them does not itself establish that Google has verified ownership.

## Build and publish

The site uses Zensical’s modern theme with separate guide, help and legal sections. Shared artwork is staged from `others/assests` by `tools/docs/build.py`; source Markdown remains usable in GitHub.

The documentation workflow builds and deploys after relevant changes reach `main`. GitHub Pages must use **GitHub Actions** as its source. A local build needs the pinned `requirements-docs.txt` packages and fresh staging/output directories outside the checkout:

```sh
python tools/docs/build.py --workspace /path/to/fresh-staging --site-dir /path/to/site
```

The app's six OCR languages are independent of website language. The documentation and privacy policy are currently written in English.
