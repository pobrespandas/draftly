import Foundation

enum DefaultActionStatistics {
    static let requireText = #"if (draft.content.length === 0) { alert('Empty draft. Text required to calculate statistics.'); context.cancel(); }"#

    // Match the default action's English readability rules, including its token boundaries.
    static let calculate = #"""
    function prepare(text) {
        ['li','p','h1','h2','h3','h4','h5','h6','dd'].forEach(function(tag) {
            text = text.replace('</' + tag + '>', '.');
        });
        return text.replace(/<[^>]+>/g, '').replace(/[,:;()\-]/, ' ')
            .replace(/[.!?]/, '.').replace(/^\s+/, '')
            .replace(/[ ]*(\n|\r\n|\r)[ ]*/, ' ').replace(/([.])[. ]+/, '.')
            .replace(/[ ]*([.])/, '. ').replace(/\s+/, ' ').replace(/\s+$/, '') + '.';
    }
    function syllables(token) {
        var word = token.toLowerCase().replace(/[^a-z]/g, '');
        var exceptions = {simile:3, forever:3, shoreline:2};
        if (Object.prototype.hasOwnProperty.call(exceptions, word)) return exceptions[word];
        var count = 0;
        [/^un/, /^fore/, /ly$/, /less$/, /ful$/, /ers?$/, /ings?$/].forEach(function(rule) {
            if (rule.test(word)) { word = word.replace(rule, ''); count++; }
        });
        count += (word.match(/[aeiouy]+/g) || []).length;
        [/cial/, /tia/, /cius/, /cious/, /giu/, /ion/, /iou/, /sia$/, /[^aeiuoyt]{2,}ed$/,
         /.ely$/, /[cg]h?e[rsd]?$/, /rved?$/, /[aeiouy][dt]es?$/,
         /[aeiouy][^aeiouydt]e[rsd]?$/, /^[dr]e[aeiou][^aeiou]+$/, /[aeiouy]rse$/]
            .forEach(function(rule) { if (rule.test(word)) count--; });
        [/ia/, /riet/, /dien/, /iu/, /io/, /ii/, /[aeiouym]bl$/, /[aeiou]{3}/,
         /^mc/, /ism$/, /([^aeiouy])\1l$/, /[^l]lien/, /^coa[dglx]./, /[^gq]ua[^auieo]/,
         /dnt$/, /uity$/, /ie(r|st)$/]
            .forEach(function(rule) { if (rule.test(word)) count++; });
        return count || 1;
    }
    var text = prepare(draft.content);
    function input(value) { return value ? prepare(value) : text; }
    function words(value) { return input(value).split(/[^a-z0-9]+/i).length || 1; }
    function sentences(value) { return input(value).replace(/[^.!?]/g, '').length || 1; }
    function letters(value) { return input(value).replace(/[^a-z]+/ig, '').length; }
    function averageWords(value) {
        var source = input(value);
        return words(source) / sentences(source);
    }
    function averageSyllables(value) {
        var source = input(value), count = 0;
        source.split(/\s+/).forEach(function(word) { count += syllables(word); });
        return (count || 1) / words(source);
    }
    function complexWords(value, includeNames) {
        return input(value).split(/\s+/).filter(function(word) {
            return (includeNames !== false || !/^[A-Z]/.test(word)) && syllables(word) > 2;
        }).length;
    }
    function complexPercentage(value) {
        var source = input(value);
        return complexWords(source, false) / words(source) * 100;
    }
    function tenth(value) { return Math.round(value * 10) / 10; }
    var rows = [
        ['Words', words()],
        ['Sentences', sentences()],
        ['Words per sentence', Math.round(averageWords())],
        ['Flesch-Kincaid Ease', tenth(206.835 - 1.015 * averageWords(text) - 84.6 * averageSyllables(text)),
            'http://www.readabilityformulas.com/flesch-reading-ease-readability-formula.php'],
        ['Flesch-Kincaid Grade Level', tenth(0.39 * averageWords(text) + 11.8 * averageSyllables(text) - 15.59),
            'http://www.readabilityformulas.com/flesch-grade-level-readability-formula.php'],
        ['Gunning Fog', tenth((averageWords(text) + complexPercentage(text)) * 0.4),
            'https://en.wikipedia.org/wiki/Gunning_fog_index'],
        ['SMOG Index', tenth(1.043 * Math.sqrt(complexWords(text) * 30 / sentences(text) + 3.1291)),
            'http://www.readabilityformulas.com/smog-readability-formula.php'],
        ['Automated Readability', tenth(4.71 * letters(text) / words(text) + 0.5 * words(text) / sentences(text) - 21.43),
            'http://www.readabilityformulas.com/automated-readability-index.php'],
        ['Coleman Liau', tenth(5.89 * letters(text) / words(text) - 0.3 * sentences(text) / words(text) - 15.8),
            'http://www.readabilityformulas.com/coleman-liau-readability-formula.php']
    ];
    draft.setTemplateTag('htmltable', '<table>' + rows.map(function(row) {
        return '<tr><td class="lbl">' + row[0] + '</td><td class="val">' + row[1] +
            '</td><td>' + (row[2] ? '<a href="' + row[2] + '">info</a>' : '') + '</td></tr>';
    }).join('') + '</table>');
    """#

    static let theme = #"draft.setTemplateTag('bodystyle', app.themeMode === 'dark' ? 'html, body { background: #222; color: #ddd; }' : 'html, body { background: #fff; color: #444; }');"#

    static let preview = """
    <!DOCTYPE html><html dir="auto"><head><title>Preview</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    html, body { padding: 0; margin: auto; max-width: 55em; text-align: center; }
    body { font: 1.3em "Vollkorn", Palatino, Times; line-height: 1.4; }
    h2 { font-weight: normal; }
    a { color: #2484c1; text-decoration: none; }
    a:hover { text-decoration: underline; }
    table { margin: 1em auto; border: 1px solid #aaa; border-collapse: collapse; }
    td { padding: .25em .5em; text-align: left; border: 1px solid #ccc; }
    .val { font-weight: bold; text-align: right; }
    @media only screen and (max-device-width: 1024px) { body { font-size: 120%; } }
    [[bodystyle]]
    </style></head><body><h2>Draft Statistics</h2>[[htmltable]]</body></html>
    """
}
