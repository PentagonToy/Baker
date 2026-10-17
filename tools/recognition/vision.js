// Run macOS Vision directly; no app or user document is controlled.
ObjC.import('Foundation');
ObjC.import('Vision');

function run(args) {
    const manifest = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0], $.NSUTF8StringEncoding, null));
    const rows = manifest.trim().split('\n').map(JSON.parse).filter(row => row.kind === 'text');
    const languageNames = {en:'en-US',de:'de-DE',ko:'ko-KR',sv:'sv-SE',da:'da-DK',fi:'fi-FI'};
    const results = [];
    rows.forEach(row => {
        const request = $.VNRecognizeTextRequest.alloc.init;
        request.recognitionLevel = 0;
        request.usesLanguageCorrection = true;
        const error = Ref();
        const supported = ObjC.deepUnwrap(request.supportedRecognitionLanguagesAndReturnError(error));
        const desired = languageNames[row.language];
        const selected = supported.filter(language => language === desired || language.split('-')[0] === row.language);
        if (!selected.length) {
            results.push({id:row.id,prediction:'',seconds:0,error:'Language unsupported by this macOS Vision revision',supported_languages:supported});
            return;
        }
        request.recognitionLanguages = $(selected.slice(0,1));
        const handler = $.VNImageRequestHandler.alloc.initWithURLOptions($.NSURL.fileURLWithPath(row.image), $({}));
        const started = Date.now();
        const success = handler.performRequestsError($([request]),error);
        const observations = request.results;
        const lines = [];
        if (success) {
            for (let i=0; i<observations.count; i++) {
                const candidates = observations.objectAtIndex(i).topCandidates(1);
                if (candidates.count) lines.push(ObjC.unwrap(candidates.objectAtIndex(0).string));
            }
        }
        results.push({id:row.id,prediction:lines.join('\n'),seconds:(Date.now()-started)/1000,language:selected[0],error:success?null:ObjC.unwrap(error[0].localizedDescription)});
    });
    const output = results.map(row => JSON.stringify(row)).join('\n')+'\n';
    const success = $(output).writeToFileAtomicallyEncodingError(args[1],true,$.NSUTF8StringEncoding,null);
    if (!success) throw Error('Could not write Vision results');
    return JSON.stringify({cases:results.length,unsupported:results.filter(row => row.error).length});
}
