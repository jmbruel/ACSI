all: *.txt
	@echo '==> Compiling asciidoc files to generate HTML'
	asciidoc -a posix --unsafe make.txt

dessins: dessins/*.txt
	@echo '==> Compiling pychart files'
	java -jar /Users/bruel/dev/ditaa0_9/ditaa0_9.jar -r -o dessins/*.txt

compact:
	@echo '==> Compiling asciidoc files to generate compact HTML'
	asciidoc -a theme=compact -a icons -a iconsdir=./images/icons main.txt -o main.compact.html

slidy:
	@echo '==> Compiling asciidoc files to generate HTML'
	asciidoc -a posix --unsafe make.txt

co: 
	@echo '==> Checkout de la dernière version'
	git checkout master

commit: 
	@echo '==> Commit de la dernière version'
	git add .
	git commit -m "maj by JMB"

github:
	@echo '==> Create github repo'
	git remote add origin https://github.com/jmbruel/ACSI.git

push:
	@echo '==> Pushing to gitub'
	cp main.html main.slidy.html /Users/bruel/Dropbox/Public/dev/ACSI
	git push -u origin master

init:
	@echo '==> Repository initial'
	git init

clean: 
	@echo '==> Suppression des fichiers de compilation'
	@# fichiers de compilation latex
	@rm -f *.log *.aux *.dvi *.toc *.lot *.lof *.ilg
	@# fichiers de bibtex
	@rm -f *.blg
