fs = require 'fs'
path = require 'path'
async = require 'async'
coffee = require 'coffee-script'
less = require 'less'
jsp = require('uglify-js').parser
pro = require('uglify-js').uglify
EventEmitter = require('events').EventEmitter

wait = (milliseconds, func) -> setTimeout func, milliseconds
compilationError = 'compilation error'

class Collate
	collate: (target, sources, options, callback) ->
		options ?= {}
		options.compress ?= true
		options.verbose ?= false

		collator = new _Collator target, sources, options, callback
		collator.collate()
		return collator

class _Collator extends EventEmitter
	constructor: (@target, @sources, @options, @callback) ->
		
		if options.basedir?	# Prepend with baseDir if it exists
			@target = path.join @options.basedir, @target
			@sources = (path.join @options.basedir, source for source in @sources)
		
		# Make all paths absolute
		@target = path.resolve @target
		@sources = (path.resolve source for source in @sources)

		async.map @sources, fs.stat, (err, stats) => # Get baseline file metadata/check for existence
			if err
				console.error err
				@options.watch = false # Don't watch if files don't exist
			else
				@_stats = stats

	collate: =>
		async.series [@_compileSources, @_writeTarget], (err, results) =>
			if @options.verbose and not err
				console.log "#{(new Date).toLocaleTimeString()} - collated #{path.basename @target}"
				@emit 'collate', msg
			if err and err isnt compilationError
				@emit 'error',err
				console.error err
			if @callback?
				@callback err
			if @options.watch
				@_rewatch()

	_watchEvent: (event, filename) =>
		clearTimeout @_watchTimeout
		@_watchTimeout = wait 100, => # Catch multiple near-simultaneous watch events only once
			watcher.close() for watcher in @_watchers # Kill the existing watchers once one goes off
			async.map @sources, fs.stat, (err, stats) => # Get the new stats
				for stat, i in stats
					prev = @_stats[i]
					if stat.size isnt prev.size or stat.mtime.getTime() isnt prev.mtime.getTime()
						if @options.verbose
							@emit 'change',msg
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
			@_compiledSources = []
			for source, i in @sources
				@_compiledSources[i] = null
		compileIfChanged = (i, _callback) =>
			if not @_compiledSources[i]?
				@_compileSource @sources[i], (err, result) =>
					if result
						@_compiledSources[i] = result
					else
						@_compiledSources[i] = compilationError
					_callback null
			else
				_callback null

		async.map [0...@_compiledSources.length], compileIfChanged, callback

# This function never calls back with an error, which allows multiple errors to be logged if necessary.
# The errors all get sopped up by _writeTarget below when it checks for null compiled sources.
	_compileSource: (source, callback) =>
		ext = path.extname source
		compress = @options.compress
	
		uglify = (js) ->
			try
				ast = jsp.parse js
			catch e
				console.error "In #{path.basename source}, line #{e.line}, col #{e.col} - #{e.message}"
				return null
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
					try
						result = coffee.compile result
					catch e
						console.error "In #{path.basename source} - #{e}"
						result = null
					result = uglify result if compress and result
					_callback null, result
				when '.css', '.less'
# Less can be finicky about finding @imported files
					less_options =
						filename: source
						paths: [path.dirname source]
						
					new (less.Parser)(less_options).parse result, (e, tree) ->
						logLessErr = (e) ->
							console.error "In #{path.basename source}, line #{e.line}, col #{e.column} - #{e.type}: #{e.message}"
						
						if e
							logLessErr e
							result = null
						else
							try # Can throw errors for missing imports, etc.
								result = tree.toCSS { compress: compress }
							catch e
								logLessErr e
								result = null
						_callback null, result
	
		async.waterfall [read, compile], callback
		
	_writeTarget: (callback) =>
		if @_compiledSources.indexOf(compilationError) is -1 # No compilation errors
			ws = fs.createWriteStream @target
			for compiledSource in @_compiledSources
				ws.write compiledSource
				if @target.indexOf('.js') isnt -1 and @options.compress # Close out minified javascript lines appropriately
					ws.write ';\n'
			ws.end()
			callback null
		else
			callback compilationError
	
module.exports = new Collate