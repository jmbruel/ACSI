#
# Copyright (C) 2009-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::ods;

use AMC::Basic;
use AMC::Export;
use Encode;

use Module::Load::Conditional qw/can_load/;

use OpenOffice::OODoc;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.nom'}="";
    $self->{'out.code'}="";
    $self->{'out.columns'}='student.key,student.name';
    $self->{'out.font'}="Arial";
    $self->{'out.size'}="10";
    $self->{'out.stats'}='';
    $self->{'out.statsindic'}='';
    if(can_load(modules=>{'Gtk2'=>undef,'Cairo'=>undef})) {
      debug "Using Gtk2/Cairo to compute column width";
      $self->{'calc.Gtk2'}=1;
    }
    bless ($self, $class);
    return $self;
}

sub load {
  my ($self)=@_;
  $self->SUPER::load();
  $self->{'_capture'}=$self->{'_data'}->module('capture');
}

# returns the column width (in cm) to use when including the given texts.

sub text_width {
  my ($self,$title,@t)=@_;
  my $width=0;

  if($self->{'calc.Gtk2'}) {

    my $font=Pango::FontDescription->from_string($self->{'out.font'}." ".(10*$self->{'out.size'}));
    $font->set_stretch('normal');

    my $surface = Cairo::ImageSurface->create('argb32', 10,10);
    my $cr      = Cairo::Context->create($surface);
    my $layout  = Pango::Cairo::create_layout($cr);

    $font->set_weight('bold');
    $layout->set_font_description($font);
    $layout->set_text($title);
    ($width,undef)=$layout->get_pixel_size();

    $font->set_weight('normal');
    $layout->set_font_description($font);
    for my $text (@t) {
      $layout->set_text($text);
      my ($text_x,$text_y)=$layout->get_pixel_size();
      $width=$text_x if($text_x>$width);
    }

    return( 0.002772 * $width + 0.019891 + 0.3 );

  } else {
    $width=length($title);
    for my $text (@t) {
      $width=length($text) if(length($text)>$width);
    }
    return(0.22*$width+0.3);
  }
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($self->parse_string($n));
}

sub parse_string {
    my ($self,$s)=@_;
    if($self->{'out.entoure'}) {
	$s =~ s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
	$s=$self->{'out.entoure'}.$s.$self->{'out.entoure'};
    }
    return($s);
}

sub x2ooo {
    my ($x)=@_;
    my $c='';
    my $d=int($x/26);
    $x=$x % 26;
    $c.=chr(ord("A")+$d-1) if($d>0);
    $c.=chr(ord("A")+$x);
    return($c);
}

sub yx2ooo {
    my ($y,$x,$fy,$fx)=@_;
    return(($fx ? '$' : '').x2ooo($x).($fy ? '$' : '').($y+1));
}

sub subcolumn_range {
    my ($column,$a,$b)=@_;
    if($a==$b) {
	return("[.".$column.($a+1)."]");
    } else {
	return("[.".$column.($a+1).":".".".$column.($b+1)."]");
    }
}

sub subrow_range {
    my ($row,$a,$b)=@_;
    if($a==$b) {
	return("[.".x2ooo($a).($row+1)."]");
    } else {
	return("[.".x2ooo($a).($row+1).":".".".x2ooo($b).($row+1)."]");
    }
}

sub condensed {
    my ($range,$column,@lines)=@_;
    my @l=sort { $a <=> $b } @lines;
    my $debut='';
    my $fin='';
    my @sets=();
    for my $i (@l) {
	if($debut) {
	    if($i == $fin+1) {
		$fin=$i;
	    } else {
		push @sets,&$range($column,$debut,$fin);
		$debut=$i;
		$fin=$i;
	    }
	} else {
	    $debut=$i;
	    $fin=$i;
	}
    }
    push @sets,&$range($column,$debut,$fin);
    return(join(";",@sets));
}

sub subcolumn_condensed {
  my ($column,@rows)=@_;
  return(condensed(\&subcolumn_range,$column,@rows));
}

sub subrow_condensed {
  my ($row,@columns)=@_;
  return(condensed(\&subrow_range,$row,@columns));
}

my %largeurs=(qw/ASSOC 4cm
	      note 1.5cm
	      total 1.2cm
	      max 1cm
	      heads 3cm/);

my %style_col=(qw/student.key CodeA
	       NOM General
	       NOTE NoteF
	       student.copy NumCopie
	       TOTAL NoteQ
	       MAX NoteQ
	       HEAD General
	       /);
my %style_col_abs=(qw/NOTE General
	       ID NoteX
	       TOTAL NoteX
	       MAX NoteX
	       /);

my %fonction_arrondi=(qw/i ROUNDDOWN
		      n ROUND
		      s ROUNDUP
		      /);

sub set_cell {
  my ($doc,$feuille,$jj,$ii,$abs,$x,$value,%oo)=@_;

  $value=encode('utf-8',$value) if($oo{'utf8'});
  $doc->cellValueType($feuille,$jj,$ii,'float')
    if($oo{'numeric'} && !$abs);
  $doc->cellStyle($feuille,$jj,$ii,
		  ($abs && $style_col_abs{$x}
		   ? $style_col_abs{$x} : ($style_col{$x} ? $style_col{$x} : $style_col{'HEAD'})));
  if($oo{'formula'}) {
    $doc->cellFormula($feuille,$jj,$ii,$oo{'formula'});
  } else {
    $doc->cellValue($feuille,$jj,$ii,$value);
  }
}

sub build_stats_table {
  my ($self,$cts,$correct_data,$doc,$stats,@q)=@_;

  my %xbase=();

  my $ybase=0;
  my $x=0;
  for my $q (@q) {
    $doc->cellSpan($stats,$ybase,$x,4);
    $doc->cellStyle($stats,$ybase,$x,
		    'StatsQName'.(!$correct_data ? 'I' :'S'));
    $doc->cellValue($stats,$ybase,$x,encode('utf-8',$q->{'title'}));

    $doc->cellStyle($stats,$ybase+1,$x,'statCol');
# TRANSLATORS: this is a head name in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding column contains the reference of the boxes. Please let this name short.
    $doc->cellValue($stats,$ybase+1,$x,encode('utf-8',__("Box")));
    $doc->cellStyle($stats,$ybase+1,$x+1,'statCol');
# TRANSLATORS: this is a head name in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding column contains the number of items (ticked boxes, or invalid or empty questions). Please let this name short.
    $doc->cellValue($stats,$ybase+1,$x+1,encode('utf-8',__("Nb")));
    $doc->cellStyle($stats,$ybase+1,$x+2,'statCol');
# TRANSLATORS: this is a head name in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding column contains percentage of questions for which the corresponding box is ticked over all questions. Please let this name short.
    $doc->cellValue($stats,$ybase+1,$x+2,encode('utf-8',__("/all")));
# TRANSLATORS: this is a head name in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding column contains percentage of questions for which the corresponding box is ticked over the expressed questions (counting only questions that did not get empty or invalid answers). Please let this name short.
    $doc->cellStyle($stats,$ybase+1,$x+3,'statCol');
    $doc->cellValue($stats,$ybase+1,$x+3,encode('utf-8',__("/expr")));

    $doc->columnStyle($stats,$x+4,"col.Space");

    $xbase{$q->{'question'}}=$x;
    $x+=5;
  }

  my %y_item=('all'=>2,'empty'=>3,'invalid'=>4);
# TRANSLATORS: this is a row label in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding row contains the total number of sheets. Please let this label short.
  my %y_name=('all'=>__"ALL",
# TRANSLATORS: this is a row label in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding row contains the number of sheets for which the question did not get an answer. Please let this label short.
	      'empty'=>__"NA",
# TRANSLATORS: this is a row label in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding row contains the number of sheets for which the question got an invalid answer. Please let this label short.
	      'invalid'=>__"INVALID");
  my %y_style=('empty'=>'qidE','invalid'=>'qidI');
  my %q_amax=();

  for my $counts (sort { $a->{'answer'} eq "0" ? 1
			   : $b->{'answer'} eq "0" ? -1 : 0 } @$cts) {
    my $x=$xbase{$counts->{'question'}};
      if(defined($x)) {
	my $y=$y_item{$counts->{'answer'}};
	my $name=$y_name{$counts->{'answer'}};
	my $style=$y_style{$counts->{'answer'}};
	if(!$y) {
	  if($counts->{'answer'}>0) {
	    $q_amax{$counts->{'question'}}=$counts->{'answer'}
	      if($counts->{'answer'}>$q_amax{$counts->{'question'}});
	    $y=4+$counts->{'answer'};
	    $name=chr(ord("A")+$counts->{'answer'}-1);
	  } else {
	    $q_amax{$counts->{'question'}}++;
	    $y=4+$q_amax{$counts->{'question'}};
# TRANSLATORS: this is a row label in the table with questions basic statistics in the ODS exported spreadsheet. The corresponding row contains the number of sheets for which the question got the "none of the above are correct" answer. Please let this label short.
	    $name=__"NONE";
	  }
	}
	$doc->cellStyle($stats,$ybase+$y,$x+1,'NumCopie');
	$doc->cellValueType($stats,$ybase+$y,$x+1,'float');
	$doc->cellValue($stats,$ybase+$y,$x+1,$counts->{'nb'});
	$doc->cellStyle($stats,$ybase+$y,$x,($style ? $style : 'General'));
	$doc->cellValue($stats,$ybase+$y,$x,encode('utf-8',$name));
      }
    }

  for my $q (@q) {
    my $xb=$xbase{$q->{'question'}};

    for my $y (3,4) {
      $doc->cellStyle($stats,$ybase+$y,$xb+2,'Qpc');
      $doc->cellValueType($stats,$ybase+$y,$xb+2,'float');
      $doc->cellFormula($stats,$ybase+$y,$xb+2,
			"oooc:=[.".yx2ooo($ybase+$y,$xb+1)."]/[."
			.yx2ooo($ybase+2,$xb+1)."]");
    }

    for my $i (1..$q_amax{$q->{'question'}}) {
      my $y=$ybase+4+$i;
      $doc->cellStyle($stats,$y,$xb+2,'Qpc');
      $doc->cellValueType($stats,$y,$xb+2,'float');
      $doc->cellFormula($stats,$y,$xb+2,
			"oooc:=[.".yx2ooo($y,$xb+1)."]/[."
			.yx2ooo($ybase+2,$xb+1)."]");

      $doc->cellStyle($stats,$y,$xb+3,'Qpc');
      $doc->cellValueType($stats,$y,$xb+3,'float');
      $doc->cellFormula($stats,$y,$xb+3,
			"oooc:=[.".yx2ooo($y,$xb+1)."]/([."
			.yx2ooo($ybase+2,$xb+1)."]-[."
			.yx2ooo($ybase+3,$xb+1)."]-[."
			.yx2ooo($ybase+4,$xb+1)."])");
    }
  }

  for my $c (@$correct_data) {
    my $x=$xbase{$c->{'question'}};
    if(defined($x)) {
      my $y=4+$c->{'answer'};
      $y=4+$q_amax{$c->{'question'}} if($c->{'answer'}==0);
      $doc->cellStyle($stats,$ybase+$y,$x,
		      $c->{'correct_max'}==0 ? 'qidW' :
		      $c->{'correct_min'}==1 ? 'qidC' :
		      'qidX');
    }
  }

}

sub export {
    my ($self,$fichier)=@_;

    $self->pre_process();

    $self->{'_scoring'}->begin_read_transaction('XODS');

    my $grain=$self->{'_scoring'}->variable('granularity');
    my $ndg=0;
    if($grain =~ /[.,]([0-9]*[1-9])/) {
	$ndg=length($1);
    }

    my $rd=$self->{'_scoring'}->variable('rounding');
    my $arrondi='';
    if($rd =~ /^([ins])/i) {
      $arrondi=$fonction_arrondi{$1};
    } else {
      debug "Unknown rounding type: $rd";
    }

    my $lk=$self->{'_assoc'}->variable('key_in_list');

    my $notemin=$self->{'_scoring'}->variable('mark_floor');
    my $plafond=$self->{'_scoring'}->variable('ceiling');

    $notemin='' if($notemin =~ /[a-z]/i);

    my $la_date = odfLocaltime();

    my $archive = odfContainer($fichier,
			       create => 'spreadsheet');

    my $doc=odfConnector(container	=> $archive,
			 part		=> 'content',
			 );
    my $styles=odfConnector(container	=> $archive,
			    part		=> 'styles',
			    );

    my %col_styles=();

    $doc->createStyle('col.notes',
		      family=>'table-column',
		      properties=>{
			  -area=>'table-column',
			  'column-width' => "1cm",
		      },
		      );
    $col_styles{'notes'}=1;

    for(keys %largeurs) {
	$doc->createStyle('col.'.$_,
			  family=>'table-column',
			  properties=>{
			      -area=>'table-column',
			      'column-width' => $largeurs{$_},
			  },
			  );
	$col_styles{$_}=1;
    }

    $styles->createStyle('DeuxDecimales',
			 namespace=>'number',
			 type=>'number-style',
			 properties=>{
			     'number:decimal-places'=>"2",
			     'number:min-integer-digits'=>"1",
			     'number:grouping'=>'true', # espace tous les 3 chiffres
			     'number:decimal-replacement'=>"", # n'ecrit pas les decimales nulles
			 },
			 );

    my $pc=$styles->createStyle('Percentage',
				namespace=>'number',
				type=>'percentage-style',
				properties=>{
				    'number:decimal-places'=>"0",
				    'number:min-integer-digits'=>"1",
				},
	);
    $styles->appendElement($pc,'number:text','text'=>'%');


    $styles->createStyle('NombreVide',
			 namespace=>'number',
			 type=>'number-style',
			 properties=>{
			     'number:decimal-places'=>"0",
			     'number:min-integer-digits'=>"0",
			     'number:grouping'=>'true', # espace tous les 3 chiffres
			     'number:decimal-replacement'=>"", # n'ecrit pas les decimales nulles
			 },
			 );

    $styles->createStyle('num.Note',
			 namespace=>'number',
			 type=>'number-style',
			 properties=>{
			     'number:decimal-places'=>$ndg,
			     'number:min-integer-digits'=>"1",
			     'number:grouping'=>'true', # espace tous les 3 chiffres
			 },
			 );

    $styles->createStyle('Tableau',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'fo:border'=>"0.039cm solid \#000000", # epaisseur trait / solid|double / couleur
			 },
			 );

    # General
    $styles->createStyle('General',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "start",
			     'fo:margin-left' => "0.1cm",
			 },
			 'references'=>{'style:data-style-name' => 'Percentage'},
			 );
    # Qpc : pourcentage de reussite global pour une question
    $styles->createStyle('Qpc',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 'references'=>{'style:data-style-name' => 'Percentage'},
			 );

    # StatsQName : nom de question
    $styles->createStyle('StatsQName',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );
    $styles->updateStyle('StatsQName',
			 properties=>{
				      -area=>'text',
				      'fo:font-weight'=>'bold',
				      'fo:font-size'=>"14pt",
			 },
			 );
    $styles->createStyle('StatsQNameS',
			 'parent'=>'StatsQName',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#c4ddff",
				     },
			);
    $styles->createStyle('StatsQNameM',
			 'parent'=>'StatsQName',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#f5c4ff",
				     },
			);
    $styles->createStyle('StatsQNameI',
			 'parent'=>'StatsQName',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#e6e6ff",
				     },
			);

    $styles->createStyle('statCol',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );
    $styles->updateStyle('statCol',
			 properties=>{
				      -area=>'text',
				      'fo:font-weight'=>'bold',
			 },
			 );

    $styles->createStyle('qidW',
			 'parent'=>'General',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#ffc8a0",
				     },
			);
    $styles->createStyle('qidC',
			 'parent'=>'General',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#c9ffd1",
				     },
			);
    $styles->createStyle('qidX',
			 'parent'=>'General',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#e2e2e2",
				     },
			);
    $styles->createStyle('qidI',
			 'parent'=>'General',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#ffbaba",
				     },
			);
    $styles->createStyle('qidE',
			 'parent'=>'General',
			 family=>'table-cell',
			 properties=>{
				      -area => 'table-cell',
				      'fo:background-color'=>"#ffff99",
				     },
			);

    $doc->createStyle("col.Space",
		      family=>'table-column',
		      properties=>{
				   -area=>'table-column',
				   'column-width' => "4mm",
				  },
		     );

    # NoteQ : note pour une question
    $styles->createStyle('NoteQ',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 'references'=>{'style:data-style-name' => 'DeuxDecimales'},
			 );

    # NoteV : note car pas de reponse
    $styles->createStyle('NoteV',
			 parent=>'NoteQ',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'fo:background-color'=>"#ffff99",
			 },
			 'references'=>{'style:data-style-name' => 'NombreVide'},
			 );

    # NoteE : note car erreur "de syntaxe"
    $styles->createStyle('NoteE',
			 parent=>'NoteQ',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'fo:background-color'=>"#ffbaba",
			 },
			 'references'=>{'style:data-style-name' => 'NombreVide'},
			 );

    # NoteX : pas de note car la question ne figure pas dans cette copie la
    $styles->createStyle('NoteX',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 'references'=>{'style:data-style-name' => 'NombreVide'},
			 );

    $styles->updateStyle('NoteX',
			 properties=>{
			     -area=>'table-cell',
			     'fo:background-color'=>"#b3b3b3",
			 },
			 );

    # CodeV : entree de AMCcode
    $styles->createStyle('CodeV',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );

    $styles->updateStyle('CodeV',
			 properties=>{
			     -area=>'table-cell',
			     'fo:background-color'=>"#e6e6ff",
			 },
			 );

    # CodeA : code d'association
    $styles->createStyle('CodeA',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );

    $styles->updateStyle('CodeA',
			 properties=>{
			     -area=>'table-cell',
			     'fo:background-color'=>"#ffddc4",
			 },
			 );

    # NoteF : note finale pour la copie
    $styles->createStyle('NoteF',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "right",
			 },
			 'references'=>{'style:data-style-name' => 'num.Note'},
			 );

    $styles->updateStyle('NoteF',
			 properties=>{
			     -area=>'table-cell',
			     'fo:padding-right'=>"0.2cm",
			 },
			 );

    $styles->createStyle('Titre',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'text',
			     'fo:font-weight'=>'bold',
			     'fo:font-size'=>"16pt",
			 },
			 );

    $styles->createStyle('NumCopie',
			 parent=>'Tableau',
			 family=>'table-cell',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align' => "center",
			 },
			 );

    $styles->createStyle('Entete',
			 parent=>'Default',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'vertical-align'=>"bottom",
			     'horizontal-align' => "middle",
			     'fo:padding'=>'1mm', # espace entourant le contenu
			     'fo:border'=>"0.039cm solid \#000000", # epaisseur trait / solid|double / couleur
			 },
			 );

    $styles->updateStyle('Entete',
			 properties=>{
			     -area => 'text',
			     'fo:font-weight'=>'bold',
			 },
			 );

    $styles->updateStyle('Entete',
			 properties=>{
			     -area => 'paragraph',
			     'fo:text-align'=>"center",
			 },
			 );

    # EnteteVertical : en-tete, ecrit verticalement
    $styles->createStyle('EnteteVertical',
			 parent=>'Entete',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'style:rotation-angle'=>"90",
			 },
			 );

    # EnteteIndic : en-tete d'une question indicative
    $styles->createStyle('EnteteIndic',
			 parent=>'EnteteVertical',
			 family=>'table-cell',
			 properties=>{
			     -area => 'table-cell',
			     'fo:background-color'=>"#e6e6ff",
			 },
			 );

    my @student_columns=split(/,+/,$self->{'out.columns'});

    my @codes=$self->{'_scoring'}->codes;
    my $codes_re="(".join("|",map { "\Q$_\E" } @codes).")";
    my @questions=grep { $_->{'title'} !~ /$codes_re\.[0-9]+$/ }
      $self->{'_scoring'}->questions;
    my @questions_0=grep { $self->{'_scoring'}->one_indicative($_->{'question'},0); }
      @questions;
    my @questions_1=grep { $self->{'_scoring'}->one_indicative($_->{'question'},1); }
      @questions;

    debug "Questions: ".join(', ',map { $_->{'question'}.'='.$_->{'title'} } @questions);
    debug "Questions PLAIN: ".join(', ',map { $_->{'title'} } @questions_0);
    debug "Questions INDIC: ".join(', ',map { $_->{'title'} } @questions_1);

    my $nq=1+$#student_columns+1+$#questions_0+1+$#questions_1;

    my $dimx=3+$nq+1+$#codes;
    my $dimy=5+1+$#{$self->{'marks'}};

    my $feuille=$doc->getTable(0,$dimy,$dimx);
    $doc->expandTable($feuille, $dimy, $dimx);
    $doc->renameTable($feuille,encode('utf-8',($self->{'out.code'} ?
					       $self->{'out.code'} :
# TRANSLATORS: table name in the exported ODS spreadsheet for the table that contains the marks.
					       __("Marks")
					      )));

    if($self->{'out.nom'}) {
	$doc->cellStyle($feuille,0,0,'Titre');
	$doc->cellValue($feuille,0,0,encode('utf-8',$self->{'out.nom'}));
    }

    my $x0=0;
    my $x1=0;
    my $y0=2;
    my $y1=0;
    my $ii;
    my %code_col=();
    my %code_row=();
    my %col_cells=();
    my %col_content=();

    my $notemax;

    my $jj=$y0;

    ##########################################################################
    # first row: titles
    ##########################################################################

    $ii=$x0;
    for(@student_columns,
	qw/note total max/) {
	$doc->cellStyle($feuille,$y0,$ii,'Entete');

	$code_col{$_}=$ii;
	my $name=$_;
	$name="A:".encode('utf-8',$lk) if($name eq 'student.key');
	$name=translate_column_title('nom') if($name eq 'student.name');
	$name=translate_column_title('copie') if($name eq 'student.copy');

	$col_content{$_}=[$name];
	$doc->cellValue($feuille,$y0,$ii,
			encode('utf-8',$name));

	$ii++;
      }

    $x1=$ii;

    for(@questions_0) {
	$doc->columnStyle($feuille,$ii,'col.notes');
	$doc->cellStyle($feuille,$y0,$ii,'EnteteVertical');
	$doc->cellValue($feuille,$y0,$ii++,encode('utf-8',$_->{'title'}));
    }
    for(@questions_1) {
	$doc->columnStyle($feuille,$ii,'col.notes');
	$doc->cellStyle($feuille,$y0,$ii,'EnteteIndic');
	$doc->cellValue($feuille,$y0,$ii++,encode('utf-8',$_->{'title'}));
    }
    for(@codes) {
	$doc->cellStyle($feuille,$y0,$ii,'EnteteIndic');
	$doc->cellValue($feuille,$y0,$ii++,encode('utf-8',$_));
    }

    ##########################################################################
    # second row: maximum
    ##########################################################################

    $jj++;

    $doc->cellSpan($feuille,$jj,$code_col{'total'},2);
    $doc->cellStyle($feuille,$jj,$code_col{'total'},'General');
    $doc->cellValue($feuille,$jj,$code_col{'total'},
		    encode('utf-8',translate_id_name('max')));

    $doc->cellStyle($feuille,$jj,$code_col{'note'},'NoteF');
    $doc->cellValueType($feuille,$jj,$code_col{'note'},'float');
    $doc->cellValue($feuille,$jj,$code_col{'note'},
		    $self->{'_scoring'}->variable('mark_max'));
    $notemax='[.'.yx2ooo($jj,$code_col{'note'},1,1).']';

    $ii=$x1;
    for(@questions_0) {
      $doc->cellStyle($feuille,$jj,$ii,'NoteQ');
      $doc->cellValueType($feuille,$jj,$ii,'float');
      $doc->cellValue($feuille,$jj,$ii++,
		      $self->{'_scoring'}->question_maxmax($_->{'question'}));
    }

    $code_row{'max'}=$jj;

    ##########################################################################
    # third row: mean
    ##########################################################################

    $jj++;

    $doc->cellSpan($feuille,$jj,$code_col{'total'},2);
    $doc->cellStyle($feuille,$jj,$code_col{'total'},'General');
    $doc->cellValue($feuille,$jj,$code_col{'total'},
		    encode('utf-8',translate_id_name('moyenne')));
    $code_row{'average'}=$jj;

    ##########################################################################
    # following rows: students sheets
    ##########################################################################

    my @presents=();
    my %scores;
    my @scores_columns;

    my $y1=$jj+1;

    for my $m (@{$self->{'marks'}}) {
	$jj++;

	# @presents collects the indices of the rows corresponding to
	# students that where present at the exam.
	push @presents,$jj if(!$m->{'abs'});

	# for current student sheet, @score_columns collects the
	# indices of the columns where questions scores (only those
	# that are to be summed up to get the total student score, not
	# those from indicative questions)
	# are. $scores{$question_number} is set to one when a question
	# score is added to this list.
	%scores=();
	@scores_columns=();

	# first: special columns (association key, name, mark, sheet
	# number, total score, max score)

	$ii=$x0;

	for(@student_columns) {
	  my $value=($m->{$_} ? $m->{$_} : $m->{'student.all'}->{$_});
	  push @{$col_content{$_}},$value;
	  set_cell($doc,$feuille,$jj,$ii++,
		   $m->{'abs'},$_,
		   $value,'utf8'=>1);
	}

	if($m->{'abs'}) {
	  set_cell($doc,$feuille,$jj,$ii,1,
		   'NOTE',$m->{'mark'});
	} else {
	  set_cell($doc,$feuille,$jj,$ii,0,
		   'NOTE','','numeric'=>1,
		   'formula'=>"oooc:=IF($notemax>0;"
		   .($notemin ne '' ? "MAX($notemin;" : "")
		   .($plafond ? "MIN($notemax;" : "")
		   ."$arrondi([."
		   .yx2ooo($jj,$code_col{'total'})
		   ."]/[."
		   .yx2ooo($jj,$code_col{'max'})
		   ."]*$notemax/$grain)*$grain"
		   .($plafond ? ")" : "")
		   .($notemin ne '' ? ")" : "")
		   .";"
		   .($notemin ne '' ? "MAX($notemin;" : "")
		   ."$arrondi([."
		   .yx2ooo($jj,$code_col{'total'})
		   ."]/$grain)*$grain"
		   .($notemin ne '' ? ")" : "")
		   .")");
	}
	$ii++;

	$ii++; # see later for SUM column value...
	set_cell($doc,$feuille,$jj,$ii++,$m->{'abs'},
		 'MAX',$m->{'max'},'numeric'=>1);

	# second: columns for all questions scores

	for my $q (@questions_0,@questions_1) {
	  if($m->{'abs'}) {
	    $doc->cellStyle($feuille,$jj,$ii,'NoteX');
	  } else {
	    my $r=$self->{'_scoring'}
	      ->question_result($m->{'student'},$m->{'copy'},$q->{'question'});
	    $doc->cellValueType($feuille,$jj,$ii,'float');
	    if($self->{'_scoring'}->indicative($m->{'student'},$q->{'question'})) {
	      $doc->cellStyle($feuille,$jj,$ii,'CodeV');
	    } else {
	      if(defined($r->{'score'})) {
		if(!$scores{$q->{'question'}}) {
		  $scores{$q->{'question'}}=1;
		  push @scores_columns,$ii;
		  push @{$col_cells{$ii}},$jj;
		  if($r->{'why'} =~ /v/i) {
		    $doc->cellStyle($feuille,$jj,$ii,'NoteV');
		  } elsif($r->{'why'} =~ /e/i) {
		    $doc->cellStyle($feuille,$jj,$ii,'NoteE');
		  } else {
		    $doc->cellStyle($feuille,$jj,$ii,'NoteQ');
		  }
		} else {
		  $doc->cellStyle($feuille,$jj,$ii,'NoteX');
		}
	      } else {
		$doc->cellStyle($feuille,$jj,$ii,'NoteX');
	      }
	    }
	    $doc->cellValue($feuille,$jj,$ii,$r->{'score'});
	  }
	  $ii++;
	}

	# third: codes values

	for(@codes) {
	  $doc->cellStyle($feuille,$jj,$ii,'CodeV');
	  $doc->cellValue($feuille,$jj,$ii++,
			  $self->{'_scoring'}
			  ->student_code($m->{'student'},$m->{'copy'},$_));
	}

	# come back to add sum of the scores
	set_cell($doc,$feuille,$jj,$code_col{'total'},$m->{'abs'},
		 'TOTAL','','numeric'=>1,
		 'formula'=>"oooc:=SUM(".subrow_condensed($jj,@scores_columns).")");
    }

    ##########################################################################
    # back to row for means
    ##########################################################################

    $ii=$x1;
    for my $q (@questions_0) {
      $doc->cellStyle($feuille,$code_row{'average'},$ii,'Qpc');
      $doc->cellFormula($feuille,$code_row{'average'},$ii,
			"oooc:=AVERAGE("
			.subcolumn_condensed(x2ooo($ii),@{$col_cells{$ii}})
			.")/[.".yx2ooo($code_row{'max'},$ii)."]");

      $ii++;
    }

    $doc->cellStyle($feuille,$code_row{'average'},$code_col{'note'},'NoteF');
    $doc->cellFormula($feuille,$code_row{'average'},$code_col{'note'},
		      "oooc:=AVERAGE("
     		      .subcolumn_condensed(x2ooo($code_col{'note'}),@presents).")");

    $self->{'_scoring'}->end_transaction('XODS');

    ##########################################################################
    # try to set right column width
    ##########################################################################

    for(@student_columns) {
      if($col_styles{$_}) {
	$doc->columnStyle($feuille,$code_col{$_},"col.".$col_styles{$_});
      } else {
	my $cm=$self->text_width(@{$col_content{$_}});
	debug "Column width [$_] = $cm cm";
	$doc->createStyle("col.X.$_",
			  family=>'table-column',
			  properties=>{
				       -area=>'table-column',
				       'column-width' => $cm."cm",
				      },
			 );
	$doc->columnStyle($feuille,$code_col{$_},"col.X.$_");
      }
    }

    ##########################################################################
    # tables for questions basic statistics
    ##########################################################################

    my ($dt,$cts,$man,$correct_data);

    if($self->{'out.stats'} || $self->{'out.statsindic'}) {
      $self->{'_scoring'}->begin_read_transaction('XsLO');
      $dt=$self->{'_scoring'}->variable('darkness_threshold');
      $cts=$self->{'_capture'}->ticked_sums($dt);
      $man=$self->{'_capture'}->max_answer_number();
      $correct_data=$self->{'_scoring'}->correct_for_all
	if($self->{'out.stats'});
      $self->{'_scoring'}->end_transaction('XsLO');
    }

    if($self->{'out.stats'}) {
# TRANSLATORS: Label of the table with questions basic statistics in the exported ODS spreadsheet.
      my $stats_0=$doc->appendTable(encode('utf-8',__("Questions statistics")),6+$man,5*(1+$#questions_0));

      $self->build_stats_table($cts,$correct_data,$doc,$stats_0,@questions_0);
    }

    if($self->{'out.statsindic'}) {
# TRANSLATORS: Label of the table with indicative questions basic statistics in the exported ODS spreadsheet.
      my $stats_1=$doc->appendTable(encode('utf-8',__("Indicative questions statistics")),6+$man,5*(1+$#questions_1));

      $self->build_stats_table($cts,0,$doc,$stats_1,@questions_1);
    }

    ##########################################################################
    # Legend table
    ##########################################################################

# TRANSLATORS: Label of the table with a legend (explaination of the colors used) in the exported ODS spreadsheet.
    my $legend=$doc->appendTable(encode('utf-8',__("Legend")),8,2);

    $doc->cellSpan($legend,0,0,2);
    $doc->cellStyle($legend,0,0,'Titre');
    $doc->cellValue($legend,0,0,encode('utf-8',__("Legend")));

    $jj=2;

    $doc->cellStyle($legend,$jj,0,'NoteX');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the questions that have not been asked to some students.
    $doc->cellValue($legend,$jj,1,encode('utf-8',__("Non applicable")));
    $jj++;
    $doc->cellStyle($legend,$jj,0,'NoteV');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the questions that have not been answered.
    $doc->cellValue($legend,$jj,1,encode('utf-8',__("No answer")));
    $jj++;
    $doc->cellStyle($legend,$jj,0,'NoteE');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the questions that got an invalid answer.
    $doc->cellValue($legend,$jj,1,encode('utf-8',__("Invalid answer")));
    $jj++;
    if($self->{'out.stats'}) {
      $doc->cellStyle($legend,$jj,0,'qidC');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the questions that got an invalid answer.
      $doc->cellValue($legend,$jj,1,encode('utf-8',__("Correct answer")));
      $jj++;
      $doc->cellStyle($legend,$jj,0,'qidW');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the questions that got an invalid answer.
      $doc->cellValue($legend,$jj,1,encode('utf-8',__("Wrong answer")));
      $jj++;
    }
    $doc->cellStyle($legend,$jj,0,'CodeV');
# TRANSLATORS: From the legend in the exported ODS spreadsheet. This refers to the indicative questions.
    $doc->cellValue($legend,$jj,1,encode('utf-8',__("Indicative")));
    $jj++;

    $doc->createStyle("col.X.legend",
		      family=>'table-column',
		      properties=>{
				   -area=>'table-column',
				   'column-width' => "6cm",
				  },
		     );
    $doc->columnStyle($legend,1,"col.X.legend");

    ##########################################################################
    # set meta-data and write to file
    ##########################################################################

    my $meta = odfMeta(container => $archive);

    $meta->title(encode('utf-8',$self->{'out.nom'}));
    $meta->subject('');
    $meta->creator($ENV{'USER'});
    $meta->initial_creator($ENV{'USER'});
    $meta->creation_date($la_date);
    $meta->date($la_date);

    $archive->save;

}

1;
