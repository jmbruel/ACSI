all: *.txt
	@echo '==> Compiling asciidoc files to generate HTML'
	asciidoc -b html5 -a icons -a iconsdir=../../images/icons/ -a theme=flask -a data-uri -a numbered -a correction -o main.corrige.html main.txt
	asciidoc -b html5 -a icons -a iconsdir=../../images/icons/ -a theme=flask -a data-uri -a numbered main.txt
	
clean: 
	@echo '==> Suppression des fichiers de compilation'
	@# fichiers de compilation latex
	@rm -f *.log *.aux *.dvi *.toc *.lot *.lof *.ilg
	@# fichiers de bibtex
	@rm -f *.blg
