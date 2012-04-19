# Collate

Collate is a Node module for concatenating and minifying scripts and stylesheets. Collate works with JavaScript/CoffeeScript and CSS/LESS. The command line utility can watch for changes and automatically recollate. Collate is a project of [State Design](https://www.sharingstate.com/).

## Installation

Install via NPM:

	npm install collate
  
Use the -g flag for global access to the command line utility.

## Usage

As a module:

	Collate = require('collate');
	Collate.collate('styles.css', ['main.less', 'home.css'], { basedir: 'styles/' });
	
From the command line:

	collate -t styles.css -d styles/ main.less home.css
	
## Options

	-t, --target    Target for collated output.                     [required]
	-d, --basedir   Base dir (relative to cwd).                   				[default: '.']
	-c, --compress  Minify the output.                              [boolean]	[default: true]
	-w, --watch     Watch for changes (process will run until ^C).  [boolean]	[default: false]

The module syntax is
	
	Collate.collate([target], [sources], [options]);

## Todo

 * Option to gzip
 * Don't reminify already-minified source