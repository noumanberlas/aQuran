gulp            = require 'gulp'
gutil           = require 'gulp-util'
_               = require 'lodash'
Q               = require 'q'
combine         = require 'stream-combiner'

fs              = require 'fs'
path            = require 'path'
async           = require 'async'
glob            = require 'glob'

sqlite3         = require 'sqlite3'
properties      = require 'properties'
admZip          = require 'adm-zip'
connect         = require 'connect'

plugins = (require 'gulp-load-plugins')()
config = _.defaults gutil.env,
    target: switch
        when gutil.env.chrome then 'chrome'
        when gutil.env.firefox then 'firefox'
        else 'web' # web, chrome, firefox
    port: 7000 # on which port the server is hosted
    production: no
    minify: no # whether to minify resources for production
    sourceMaps: yes
    bump: yes # whether to increase the version of the app on 'release'
    experimental: yes # whether to use the Uthmanic script by Khaled Hosny
    download: no
    translations: yes # true, false, or an array of translations to include
    recitations: yes # whether to include recitations metadata
    styles: []
    scripts: []
    countries: []
    bower: 'src/bower'
    jade:
        locals:
            manifest: 'manifest.cache'
    bundles: [
        (file: 'ionic.js', src: [
            'ionic.bundle.js'
            'angular-sanitize.js'
            ]
        )
        (file: 'utils.js', src: [
            'async.js'
            'nedb*.js'
            'lodash*.js'
            'idbstore.js'
            ]
        )
        (file: 'ng-modules.js', src: [
            'ngStorage.js'
            'angular-audio-player*.js'
            ]
        )
    ]
    src:
        icons: 'icons/*.png'
        manifest: 'manifest.coffee'
        database: 'database/main.db'
        translations: 'resources/translations/*.trans.zip'
        translationsTxt: 'resources/translations.txt'
        hosny: 'khaledhosny-quran/quran/*.txt'
        less: 'styles/main.less'
        css: 'styles/*.css'
        jade: ['index.jade', 'views/*.jade']
        coffee: ['!chromereload.coffee', '!launcher.coffee', '!manifest.coffee', 'scripts/**/*.coffee']
        js: 'scripts/*.js'
        coffeeConcat: [
            (file: 'main.js', src: [
                'scripts/main.coffee'

                # Services
                'scripts/services/cache-service.coffee'
                'scripts/services/preferences-service.coffee'
                'scripts/services/localization-service.coffee'
                'scripts/services/api-service.coffee'
                'scripts/services/recitation-service.coffee'
                'scripts/services/content-service.coffee'
                'scripts/services/search-service.coffee'
                'scripts/services/explanation-service.coffee'
                'scripts/services/storage-service.coffee'
                'scripts/services/arabic-service.coffee'
                'scripts/services/*.coffee'

                # Factories
                'scripts/factories/explanation-factory.coffee'
                'scripts/factories/audio-src-factory.coffee'
                'scripts/factories/query-builder.coffee'
                'scripts/factories/idbstore-factory.coffee'
                'scripts/factories/*.coffee'

                'scripts/filters/*.coffee'

                # Directives
                'scripts/directives/auto-direction-directive.coffee'
                'scripts/directives/emphasize-directive.coffee'
                'scripts/directives/colorize-directive.coffee'

                # Controller
                'scripts/controllers/aya-controller.coffee'
                'scripts/controllers/preferences-controller.coffee'
                'scripts/controllers/recitations-controller.coffee'
                'scripts/controllers/explanations-controller.coffee'
                'scripts/controllers/navigation-controller.coffee'
                'scripts/controllers/search-controller.coffee'
                'scripts/controllers/reading-controller.coffee'
                ]
            )
        ]

try
    fs.mkdirSync "dist"
    fs.mkdirSync "dist/#{config.target}"
    fs.mkdirSync "dist/#{config.target}/scripts"
    fs.mkdirSync "dist/#{config.target}/resources"
    fs.mkdirSync "dist/#{config.target}/translations" if config.translations
    fs.mkdirSync "dist/#{config.target}/icons"

gulp.task 'clean', () ->
    gulp.src config.target, cwd: 'dist'
    .pipe plugins.clean()

gulp.task 'manifest', () ->
    gulp.src config.src.manifest, cwd: 'src'
    .pipe plugins.cson()
    .pipe plugins.jsonEditor (json) ->
        json.permissions = _.keys json.permissions if config.target is 'chrome'
        json
    .pipe plugins.rename (file) ->
        file.extname = '.webapp' if config.target != 'chrome'
        file
    .pipe gulp.dest "dist/#{config.target}"

gulp.task 'flags', ['translations'], () ->
    gulp.src (config.countries.map (country) -> "flags/**/#{country.toLowerCase()}.*"), cwd: "#{config.bower}/flag-icon-css"
    .pipe plugins.using()
    .pipe gulp.dest "dist/#{config.target}/flags"

gulp.task 'less', ['flags', 'css'], () ->
    gulp.src config.src.less, cwd: 'src'
    .pipe plugins.less sourceMap: config.sourceMaps, compress: config.minify, paths: config.bower
    .pipe plugins.using()
    .pipe plugins.tap (file) ->
        config.styles.push path.relative 'src', file.path
    .pipe gulp.dest "dist/#{config.target}/styles"

gulp.task 'css', () ->
    # bundle = (bundle) ->
    plugins.bowerFiles()
    .pipe plugins.filter ['**/ionic/**/*.css']
    .pipe plugins.using()
    .pipe plugins.tap (file) ->
        config.styles.push path.join 'styles', path.relative config.bower, file.path
    .pipe gulp.dest "dist/#{config.target}/styles"

    plugins.bowerFiles()
    .pipe plugins.filter ['**/fonts/*']
    .pipe gulp.dest "dist/#{config.target}/styles"

gulp.task 'amiri', () ->
    gulp.src 'resources/amiri/*.ttf', cwd: 'src', base: 'src'
    .pipe gulp.dest "dist/#{config.target}"

gulp.task 'styles', ['less', 'css', 'amiri', 'flags']

gulp.task 'jade', ['scripts', 'styles'], () ->

    scripts = config.scripts || [] # TODO
    styles = config.styles || []

    gulp.src config.src.jade, cwd: 'src', base: 'src'
    .pipe plugins.using()
    .pipe plugins.jade
        pretty: not config.minify
        locals:
            scripts: scripts
            styles: styles
    .pipe gulp.dest "dist/#{config.target}"

gulp.task 'html', ['jade']

gulp.task 'coffee', ['js'], () ->
    gulp.src config.src.coffee, cwd: 'src'
    .pipe plugins.coffee bare: yes
    .pipe (if config.minify then plugins.uglify() else gutil.noop())
    .pipe plugins.tap (file) ->
        config.scripts.push path.relative 'src', file.path
    .pipe gulp.dest "dist/#{config.target}/scripts"

gulp.task 'js', (callback) ->
    bundle = (bundle) ->
        src = bundle.src.map (file) -> "*/**/#{file}"
        gutil.log 'Bundling file', gutil.colors.cyan bundle.file + '...'
        Q.when (plugins.bowerFiles()
            # .pipe plugins.using()
            .pipe plugins.filter src
            .pipe plugins.order src
            .pipe (if config.minify then plugins.uglify() else gutil.noop())
            # .pipe plugins.using()
            .pipe plugins.concat bundle.file
            .pipe gulp.dest "dist/#{config.target}/scripts"
        )
  
    config.scripts = config.bundles.map (bundle) -> "scripts/#{bundle.file}"
    Q.all config.bundles.map bundle

gulp.task 'scripts', ['js', 'coffee']

gulp.task 'icons', () ->
    gulp.src config.src.icons, cwd: 'src'
    # .pipe plugins.optimize()
    .pipe gulp.dest "dist/#{config.target}/icons"

gulp.task 'images', ['icons']

gulp.task 'quran', (callback) ->
    db = new sqlite3.Database("src/#{config.src.database}", sqlite3.OPEN_READONLY);
    db.all 'SELECT * FROM aya ORDER BY gid', (err, rows) ->
        write = (json) ->
            fs.writeFile "dist/#{config.target}/resources/quran.json", json, callback

        if config.experimental
            # process
            files = glob.sync config.src.hosny, cwd: 'src'
            numbers = /[٠١٢٣٤٥٦٧٨٩]+/g
            strip = /\u06DD|[٠١٢٣٤٥٦٧٨٩]/g
            
            process = (file) ->
                deferred = Q.defer()
                fs.readFile (path.join 'src', file), (err, data) ->
                    if err then throw err
                    text = data.toString()
                    aya_ids = text.match numbers
                    sura_id = Number file.match /\d+/g
                    
                    text = text.replace strip, ''
                    .trim()
                    .split '\n'
                    .map (line, index) ->
                        sura_id: sura_id
                        aya_id_display: aya_ids[index]
                        uthmani: line.trim()
                    deferred.resolve text
                deferred.promise

            Q.all files.map process
            .then (suras) ->
                _.flatten suras
            .then (json) ->
                _.merge rows, json
            .then(JSON.stringify)
            .then(write)
            
        else write JSON.stringify rows

gulp.task 'search', ['quran'], () ->
    gulp.src "dist/#{config.target}/resources/quran.json"
    .pipe plugins.jsonEditor (ayas) ->
        ayas.map (aya) -> _.pick aya, 'gid', 'standard', 'standard_full'
    .pipe plugins.rename (file) ->
        file.basename = 'search'
        file
    .pipe gulp.dest "dist/#{config.target}/resources"

gulp.task 'translations', () ->
    ids = []
    urls = fs.readFileSync("src/#{config.src.translationsTxt}").toString().split /\n/g

    write = (json) ->
        fs.writeFileSync "dist/#{config.target}/resources/translations.json", json

    process = (file) ->
        deferred = Q.defer()
        gutil.log 'Processing file', gutil.colors.cyan file
        file = new admZip path.join 'src', file
        entries = file.getEntries()
        props = undefined
        async.each entries, (entry, callback) ->
            if entry.name.match /.properties$/gi
                text = entry.getData().toString 'utf-8'
                properties.parse text, (err, obj) ->
                    if err then throw err
                    props = obj
                    callback err
            else if entry.name.match /.txt$/gi
                file.extractEntryTo entry.name, "dist/#{config.target}/resources/translations", no, yes
                callback()
        , (err) ->
            if err then throw err
            deferred.resolve props

        deferred.promise

    download = (id) ->
        dest = "resources/translations/#{id}.trans.zip"
        deferred = Q.defer()
        if not config.download then deferred.resolve dest
        else
            url = _.findWhere urls, (url) -> url.match id
            # gutil.log "Downloading: #{url}"
            plugins.download url
            .pipe (gulp.dest 'src/resources/translations').on('end', () ->
                deferred.resolve dest
                )
            
        deferred.promise

    if config.translations
        if typeof config.translations is 'string'
                config.translations = config.translations.split /,/g

        urls = switch 
            when config.translations instanceof Array
                config.translations.map (id) ->
                    regex = new RegExp ".+\/#{id}.*.trans.zip$", 'gi'
                    _.where urls, (url) -> 
                        url.match regex
            else urls

        urls = _.chain(urls).flatten().uniq().value()
        ids = urls.map (file) -> file.match(/.+\/(.+).trans.zip$/i)[1]
        gutil.log 'Translations IDs', gutil.colors.green ids

        Q.all ids.map download
        .then (files) ->
            Q.all files.map process
        .then (items) ->
            config.countries = _.chain items
                .pluck 'country'
                .uniq().value()
            gutil.log 'Countries:', gutil.colors.green config.countries
            items
        .then(JSON.stringify)
        .then(write)

gulp.task 'recitations', () ->
    (
        if not config.download then gulp.src 'resources/recitations.js', cwd: 'src'
        else
            plugins.download 'http://www.everyayah.com/data/recitations.js'
            .pipe gulp.dest 'src/resources'
    )
    .pipe plugins.rename (file) ->
        file.extname = '.json'
        file
    .pipe plugins.jsonEditor (json) ->
        delete json.ayahCount
        _.chain json
        .each (item, key) ->
            item.index = Number key - 1
            item
        .toArray()
        .sortBy 'index'
        .each (item) ->
            delete item.index
            item
        .value()
    .pipe gulp.dest "dist/#{config.target}/resources"

gulp.task 'package', ['build'], () ->
    switch config.target
        when 'chrome'
            '' # Do something
        when 'firefox'
            '' # Create a zip file
        else # Standard web app
            config.jade.locals.manifest = ''

gulp.task 'release', ['clean'], () ->
    
    config.production = yes
    config.minify = yes
    
    if config.bump
        config.version += 1
        config.date = new Date()

    gulp.run 'package'

gulp.task 'data', ['quran', 'recitations', 'translations', 'search']
gulp.task 'build', ['data', 'images', 'scripts', 'styles', 'html', 'manifest']

gulp.task 'serve', () ->
    connect
    .createServer connect.static "#{__dirname}/dist/#{config.target}"
    .listen config.port, () ->
        gutil.log "Server listening on port #{config.port}"