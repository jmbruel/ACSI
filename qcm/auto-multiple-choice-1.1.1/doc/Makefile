#
# Copyright (C) 2008-2010,2012 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

SHELL=/bin/sh

include ../Makefile.conf

DOCBOOKS=$(filter-out $(wildcard *.in.xml),$(wildcard *.xml))

IMAGES=$(addprefix html/images/,$(notdir $(wildcard img_src/*.svg))) $(addprefix html/images/callouts/,$(notdir $(wildcard img_src/callouts/*.svg)))

MODELS=$(wildcard modeles/*/*.d)

all: $(filter-out %.ja.pdf,$(DOCBOOKS:.xml=.pdf)) $(DOCBOOKS:.xml=.x) $(IMAGES:.svg=.png) $(MODELS:.d=.tgz) html/index.html;

images: $(IMAGES:.svg=.png)

clean:
	rm -f $(foreach ext,1 aux cb cb2 glo idx log out toc tex html pdf ext man,*.$(ext))
	rm -f modeles/*.tgz
	rm -f modeles/**/*.tgz
	rm -f html/auto-multiple-choice.**/*.html
	rm -f html/images/callouts/*.png html/images/*.png
	rm -f *~

html/images/callouts/%.png: img_src/callouts/%.svg
	rsvg-convert -w 12 -h 12 $< -o $@

html/images/%.png: img_src/%.svg
	rsvg-convert -w 24 -h 24 $< -o $@

html/index.html: FORCE
	./index.pl $(DOCBOOKS:.xml=) > $@

%.tex: %.xml
	dblatex -t tex --xslt-opts="--nonet" --xslt-opts="--catalogs" $(DBLATEX_OPT) $< -o $@
	perl addlink.pl $@

%.pdf: %.tex
	case $< in \
	  *.ja.tex) platex $<; platex $<; dvipdf $*.dvi ;; \
	  *.tex) pdflatex $<; pdflatex $< ;; \
	esac
	rm -f $(foreach ext,aux cb cb2 glo idx log out toc,$*.$(ext))

%.x: %.ext %.man %.html ;

%.ext: %.xml
	perl extrait-fichiers.pl --liste $@ $<

%.man: %.xml
	xsltproc --nonet --catalogs --param man.charmap.use.subset "0" --param make.year.ranges "1" --param make.single.year.ranges "1" --param man.output.lang.in.name.enabled "1" $(DOCBOOK_MAN_XSL) $<
	date > $@


%.html: %.xml doc-xhtml.xsl
	rm -f html/$*/*.html
	xsltproc --nonet --catalogs --stringparam base.dir html/$*/ doc-xhtml.xsl $<
	date > $@

%.tgz: %.d
	tar czf $@ -C $< .

FORCE: ;

.PHONY: FORCE all images clean
