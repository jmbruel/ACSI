all: *.txt
	@echo '==> Compiling asciidoc files to generate HTML'
	asciidoc -b html5 -a icons -a iconsdir=../../images/icons/ -a theme=flask -a data-uri -a numbered -a correction -a toc2 -o main.corrige.html main.txt
	asciidoc -a toc2 -b html5 -a icons -a iconsdir=../../images/icons/ -a theme=flask -a data-uri -a numbered main.txt
	asciidoc -b deckjs -a icons -a iconsdir=../../images/icons/ -a data-uri -a numbered -o main.dekjs.html main.txt
	asciidoc -b slidy2 -a toc2 -a icons -a iconsdir=../../images/icons/ -a data-uri -a numbered -o main.slidy.html main.txt
	asciidoc -b slidy2 -a toc2 -a icons -a iconsdir=../../images/icons/ -a data-uri -a numbered -a correction -o main.corrigeSlidy.html main.txt
	
clean: 
	@echo '==> Suppression des fichiers de compilation'
	@# fichiers de compilation latex
	@rm -f *.log *.aux *.dvi *.toc *.lot *.lof *.ilg
	@# fichiers de bibtex
	@rm -f *.blg
