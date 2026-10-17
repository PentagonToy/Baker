'use strict';
window.bakerPreview = async function (source) {
    // KaTeX's mathematical \\ch alias is not chemformula's braced language.
    if (/\\(?:ch|chemfig)\s*\{/.test(source)) {
        throw new Error('This chemistry language is unsupported; use mhchem \\ce{...} for formula notation.');
    }
    const target = document.getElementById('formula');
    target.replaceChildren();
    // New options and macro state for every equation; definitions cannot leak to history.
    katex.render(source, target, {
        displayMode: true, output: 'htmlAndMathml', throwOnError: true,
        trust: () => { throw new Error('Links, external images and HTML are disabled in formula previews.'); },
        strict: 'error', maxExpand: 1000, maxSize: 20, macros: {}
    });
    // Trigger style/layout first so WebKit starts fetching the selected local fonts.
    target.getBoundingClientRect();
    await document.fonts.ready;
    if (Array.from(document.fonts).some(font => font.status === 'error')) {
        throw new Error('A bundled formula font could not be loaded.');
    }
    // Background WebKit surfaces do not reliably receive animation frames.
    // Reading bounds below forces layout after all requested fonts are loaded.
    const bounds = target.getBoundingClientRect();
    const width = Math.ceil(Math.max(bounds.width, target.scrollWidth));
    const height = Math.ceil(Math.max(bounds.height, target.scrollHeight));
    if (!width || !height || width > 4096 || height > 2048 || width * height > 4000000) {
        throw new Error('Formula preview exceeds its image size limit.');
    }
    return { width, height };
};
