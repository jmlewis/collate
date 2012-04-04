fs = require 'fs'
path = require 'path'
async = require 'async'
coffee = require 'coffee-script'
less = require 'less'
jsp = require('uglify-js').parser
pro = require('uglify-js').uglify

wait = (milliseconds, func) -> setTimeout func, milliseconds

class Collate
	collate: (target, sources, options) ->
		options ?= {}
		options.compress ?= true

		collator = new _Collator target, sources, options
		collator.collate()

class _Collator
	constructor: (@target, @sources, @options) ->
# Prepend with baseDir if it exists
		if options.basedir?
			@target = @options.basedir + @target
			@sources = (@options.basedir + source for source in @sources)
# Make all paths absolute
		@target = path.resolve @target
		@sources = (path.resolve source for source in @sources)

		if @options.watch
			async.map @sources, fs.stat, (err, stats) => @_stats = stats

	collate: =>
		async.series [@_compileSources, @_writeTarget], (err, results) =>
			console.log err if err
			console.log "#{(new Date).toLocaleTimeString()} - collated #{path.basename @target}"
			if @options.watch
				@_rewatch()

	_watchEvent: (event, filename) =>
		clearTimeout @_watchTimeout
		@_watchTimeout = wait 25, => # Catch multiple near-simultaneous events only once
			watcher.close() for watcher in @_watchers # Kill the existing watchers once one goes off
			async.map @sources, fs.stat, (err, stats) => # Get the new stats
				for stat, i in stats
					prev = @_stats[i]
					if stat.size isnt prev.size or stat.mtime.getTime() isnt prev.mtime.getTime()
						console.log "#{(new Date).toLocaleTimeString()} - #{path.basename @sources[i]} changed"
						@_compiledSources[i] = null # Erase compiled source for the file that has changed
						@_stats[i] = stat
				if @_compiledSources.indexOf(null) isnt -1
					@collate() # Collate will rewatch upon completion
				else # Rewatch
					@_rewatch()
					
					
	_rewatch: =>
		@_watchers = (fs.watch source, @_watchEvent for source in @sources)

	_compileSources: (callback) =>
		if not @_compiledSources # First compile, so compile everything
			async.map @sources, @_compileSource, (err, results) =>
				@_compiledSources = results
				callback err
		else # Watch event, just compile what's changed
			compileIfChanged = (i, _callback) =>
				if not @_compiledSources[i]?
					@_compileSource @sources[i], (err, result) =>
						@_compiledSources[i] = result
						_callback null
				else
					_callback null

			async.map [0...@_compiledSources.length], compileIfChanged, callback

	_compileSource: (source, callback) =>
		ext = path.extname source
		compress = @options.compress
	
		uglify = (js) ->
			ast = jsp.parse js
			ast = pro.ast_mangle ast
			ast = pro.ast_squeeze ast
			return pro.gen_code(ast)
			
		read = (_callback) ->
			fs.readFile source, _callback

		compile = (result, _callback) ->
			result = result.toString()
			switch ext
				when '.js'
					result = uglify result if compress
					_callback null, result
				when '.coffee'
					result = coffee.compile result
					result = uglify result if compress
					_callback null, result
				when '.css', '.less'
# Less can be finicky about finding @imported files
					less_options =
						filename: source
						paths: [path.dirname source]
						
					new (less.Parser)(less_options).parse result, (err, tree) ->
						result = tree.toCSS { compress: compress } unless err
						_callback err, result
	
		async.waterfall [read, compile], callback
		
	_writeTarget: (callback) =>
		ws = fs.createWriteStream @target
		for compiledSource in @_compiledSources
			ws.write compiledSource
			if @target.indexOf '.js' isnt -1 # Close out javascript lines appropriately
				ws.write ';\n'
		ws.end()
		callback null
	
module.exports = new Collate