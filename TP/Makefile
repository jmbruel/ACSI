ASCIIDOC=asciidoc -b html5 -a icons -a iconsdir=../../images/icons/ -a data-uri -a numbered -a toc2

all: *.html
	
%.html: %.txt
	$(ASCIIDOC) $< 
%.corrige.html: %.txt
	$(ASCIIDOC) -a correction -o $@ $< 

clean: 
	@echo '==> Suppression des fichiers de compilation'
	@# fichiers de compilation latex
	@rm -f *.log *.aux *.dvi *.toc *.lot *.lof *.ilg
	@# fichiers de bibtex
	@rm -f *.blg
