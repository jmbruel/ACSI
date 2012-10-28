#! /usr/bin/perl -w
#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
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

use Getopt::Long;

use Gtk2 -init;
use XML::Simple;
use IO::File;
use IO::Select;
use POSIX qw/strftime/;
use Time::Local;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;
use File::Path qw/remove_tree/;
use Archive::Tar;
use Archive::Tar::File;
use Encode;
use Unicode::Normalize;
use I18N::Langinfo qw(langinfo CODESET);
use Locale::Language;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::State;
use AMC::Data;
use AMC::DataModule::capture ':zone';
use AMC::DataModule::report ':const';
use AMC::Scoring;
use AMC::Gui::Manuel;
use AMC::Gui::Association;
use AMC::Gui::Commande;
use AMC::Gui::Notes;
use AMC::Gui::Zooms;

use Data::Dumper;

use constant {
    DOC_TITRE => 0,
    DOC_MAJ => 1,

    MEP_PAGE => 0,
    MEP_ID => 1,
    MEP_MAJ => 2,

    DIAG_ID => 0,
    DIAG_ID_BACK => 1,
    DIAG_MAJ => 2,
    DIAG_EQM => 3,
    DIAG_EQM_BACK => 4,
    DIAG_DELTA => 5,
    DIAG_DELTA_BACK => 6,
    DIAG_ID_STUDENT => 7,
    DIAG_ID_PAGE => 8,
    DIAG_ID_COPY => 9,

    INCONNU_FILE => 0,
    INCONNU_SCAN => 1,
    INCONNU_TIME => 2,
    INCONNU_TIME_N => 3,
    INCONNU_PREPROC => 4,

    PROJ_NOM => 0,
    PROJ_ICO => 1,

    MODEL_NOM => 0,
    MODEL_PATH => 1,
    MODEL_DESC => 2,

    COPIE_N => 0,

    TEMPLATE_FILES_PATH => 0,
    TEMPLATE_FILES_FILE => 1,

    EMAILS_SC => 0,
    EMAILS_NAME => 1,
    EMAILS_EMAIL => 2,
    EMAILS_ID => 3,
};

Gtk2::IconTheme->get_default->prepend_search_path(amc_specdir('icons'));
Gtk2::Window->set_default_icon_list(map { Gtk2::IconTheme->get_default->load_icon("auto-multiple-choice",$_,"force-svg") } (8,16,32,48,64,128));

use_gettext;
use_amc_plugins();

my $debug=0;
my $debug_file='';

my $profile='';

GetOptions("debug!"=>\$debug,
	   "debug-file=s"=>\$debug_file,
	   "profile=s"=>\$profile,
	   );

if($debug_file) {
    my $date=strftime("%c",localtime());
    open(DBG,">>",$debug_file);
    print DBG "\n\n".('#' x 40)."\n# DEBUG - $date\n".('#' x 40)."\n\n";
    close(DBG);
    $debug=$debug_file;
}

if($debug) {
    set_debug($debug);
    debug "DEBUG MODE";
    print "DEBUG ==> ".AMC::Basic::debug_file()."\n";
}

debug_pm_version("Gtk2");

my $glade_base=__FILE__;
$glade_base =~ s/\.p[ml]$/-/i;

my $home_dir=Glib::get_home_dir();

my $o_file='';
my $o_dir=amc_user_confdir();
my $state_file="$o_dir/state.xml";

# Gets system encoding
my $encodage_systeme=langinfo(CODESET());
$encodage_systeme='UTF-8' if(!$encodage_systeme);

sub hex_color {
    my $s=shift;
    return(Gtk2::Gdk::Color->parse($s)->to_string());
}

my %w=();

# Default general options, to be used when not set in the main options
# file

my %o_defaut=('pdf_viewer'=>['commande',
			     'evince','acroread','gpdf','okular','xpdf',
			     ],
	      'img_viewer'=>['commande',
			     'eog','ristretto','gpicview','mirage','gwenview',
			     ],
	      'csv_viewer'=>['commande',
			     'gnumeric','kspread','libreoffice','localc','oocalc',
			     ],
	      'ods_viewer'=>['commande',
			     'libreoffice','localc','oocalc',
			     ],
	      'xml_viewer'=>['commande',
			     'gedit','kedit','kwrite','mousepad','leafpad',
			     ],
	      'tex_editor'=>['commande',
			     'texmaker','kile','emacs','gedit','kedit','kwrite','mousepad','leafpad',
			     ],
	      'txt_editor'=>['commande',
			     'gedit','kedit','kwrite','mousepad','emacs','leafpad',
			     ],
	      'html_browser'=>['commande',
			       'sensible-browser %u',
			       'firefox %u',
			       'galeon %u',
			       'konqueror %u',
			       'dillo %u',
			       'chromium %u',
			       ],
	      'dir_opener'=>['commande',
			     'nautilus --no-desktop file://%d',
			     'pcmanfm %d',
			     'Thunar %d',
			     'konqueror file://%d',
			     'dolphin %d',
			     ],
	      'print_command_pdf'=>['commande',
				    'cupsdoprint %f','lpr %f',
				    ],
# TRANSLATORS: directory name for projects. This directory will be created (if needed) in the home directory of the user. Please use only alphanumeric characters, and - or _. No accentuated characters.
	      'rep_projets'=>$home_dir.'/'.__"MC-Projects",
	      'rep_modeles'=>$o_dir."/Models",
	      'seuil_eqm'=>3.0,
	      'seuil_sens'=>8.0,
	      'saisie_dpi'=>150,
	      'vector_scan_density'=>250,
	      'n_procs'=>0,
	      'delimiteur_decimal'=>',',
	      'defaut_encodage_liste'=>'UTF-8',
	      'encodage_interne'=>'UTF-8',
	      'defaut_encodage_csv'=>'UTF-8',
	      'encodage_latex'=>'',
	      'defaut_moteur_latex_b'=>'pdflatex',
	      'defaut_seuil'=>0.15,
	      'taille_max_correction'=>'1000x1500',
	      'assoc_window_size'=>'',
	      'mailing_window_size'=>'',
	      'preferences_window_size'=>'',
	      'qualite_correction'=>'150',
	      'conserve_taille'=>1,
	      'methode_impression'=>'CUPS',
	      'imprimante'=>'',
	      'options_impression'=>{'sides'=>'two-sided-long-edge',
				     'number-up'=>1,
				     'repertoire'=>'/tmp',
				     },
	      'manuel_image_type'=>'xpm',
	      'assoc_ncols'=>4,
	      'zooms_ncols'=>4,
	      'tolerance_marque_inf'=>0.2,
	      'tolerance_marque_sup'=>0.2,
	      'box_size_proportion'=>0.8,
	      'bw_threshold'=>0.6,
	      'ignore_red'=>0,

	      'symboles_trait'=>2,
	      'symboles_indicatives'=>'',
	      'symbole_0_0_type'=>'none',
	      'symbole_0_0_color'=>hex_color('black'),
	      'symbole_0_1_type'=>'circle',
	      'symbole_0_1_color'=>hex_color('red'),
	      'symbole_1_0_type'=>'mark',
	      'symbole_1_0_color'=>hex_color('red'),
	      'symbole_1_1_type'=>'mark',
	      'symbole_1_1_color'=>hex_color('blue'),

	      'annote_ps_nl'=>60,
	      'annote_ecart'=>5.5,
	      'annote_chsign'=>4,

	      'ascii_filenames'=>'',

	      'defaut_annote_rtl'=>'',
# TRANSLATORS: This is the default text to be written on the top of the first page of each paper when annotating. From this string, %s will be replaced with the student final mark, %m with the maximum mark he can obtain, %S with the student total score, and %M with the maximum score the student can obtain.
	      'defaut_verdict'=>"%(ID)\n".__("Mark: %s/%m (total score: %S/%M)"),
	      'defaut_verdict_q'=>"\"%"."s/%"."m\"",

	      'zoom_window_height'=>400,
	      'zoom_window_factor'=>1.0,

	      'email_sender'=>'',
	      'email_transport'=>'sendmail',
	      'email_sendmail_path'=>['commande',
				      '/usr/sbin/sendmail','/usr/bin/sendmail',
				      '/sbin/sendmail','/bin/sendmail'],
	      'email_smtp_host'=>'smtp',
	      'email_smtp_port'=>25,
# TRANSLATORS: Subject of the emails which can be sent to the students to give them their annotated completed answer sheet.
	      'defaut_email_subject'=>__"Exam result",
# TRANSLATORS: Body text of the emails which can be sent to the students to give them their annotated completed answer sheet.
	      'defaut_email_text'=>__"Please find enclosed your annotated completed answer sheet.\nRegards.",

	      'csv_surname_headers'=>'',
	      'csv_name_headers'=>'',
	      );

# MacOSX universal command to open files or directories : /usr/bin/open
if(lc($^O) eq 'darwin') {
    for my $k (qw/pdf_viewer img_viewer csv_viewer ods_viewer xml_viewer tex_editor txt_editor dir_opener/) {
	$o_defaut{$k}=['commande','/usr/bin/open','open'];
    }
    $o_defaut{'html_browser'}=['commande','/usr/bin/open %u','open %u'];
}

# Default options for projects

my %projet_defaut=('texsrc'=>'',
		   'data'=>'data',
		   'cr'=>'cr',
		   'listeetudiants'=>'',
		   'notes'=>'notes.xml',
		   'seuil'=>'',
		   'encodage_csv'=>'',
		   'encodage_liste'=>'',
		   'maj_bareme'=>1,
		   'docs'=>['DOC-sujet.pdf','DOC-corrige.pdf','DOC-calage.xy'],
		   'filter'=>'',
		   'filtered_source'=>'DOC-filtered.tex',

		   'modele_regroupement'=>'',
		   'regroupement_compose'=>'',
		   'regroupement_type'=>'STUDENTS',
		   'regroupement_copies'=>'ALL',

		   'note_min'=>'',
		   'note_max'=>20,
		   'note_max_plafond'=>1,
		   'note_grain'=>"0.5",
		   'note_arrondi'=>'inf',

		   'liste_key'=>'',
		   'assoc_code'=>'',

		   'moteur_latex_b'=>'',

		   'nom_examen'=>'',
		   'code_examen'=>'',

		   'nombre_copies'=>0,

		   'postcorrect_student'=>0,
		   'postcorrect_copy'=>0,

		   '_modifie'=>1,
		   '_modifie_ok'=>0,

		   'format_export'=>'CSV',

		   'after_export'=>'file',
		   'export_include_abs'=>'',

		   'annote_position'=>'marge',

		   'verdict'=>'',
		   'verdict_q'=>'',
		   'annote_rtl'=>'',

		   'export_sort'=>'n',

		   'auto_capture_mode'=>-1,
		   'allocate_ids'=>0,

		   'email_col'=>'',
		   'email_subject'=>"",
		   'email_text'=>"",
		   );

# Add default project options for each export module:

my @export_modules=perl_module_search('AMC::Export::register');
for my $m (@export_modules) {
  load("AMC::Export::register::$m");
  my %d="AMC::Export::register::$m"->options_default;
  for(keys %d) {
    $projet_defaut{$_}=$d{$_};
  }
}
@export_modules=sort { "AMC::Export::register::$a"->weight
			 <=> "AMC::Export::register::$b"->weight }
  @export_modules;

# Reads filter plugins list

my @filter_modules=perl_module_search('AMC::Filter::register');
for my $m (@filter_modules) {
  load("AMC::Filter::register::$m");
}
@filter_modules=sort { "AMC::Filter::register::$a"->weight
			 <=> "AMC::Filter::register::$b"->weight }
  @filter_modules;

sub best_filter_for_file {
  my ($file)=@_;
  my $mmax='';
  my $max=-10;
  for my $m (@filter_modules) {
    my $c="AMC::Filter::register::$m"->claim($file);
    if($c>$max) {
      $max=$c;
      $mmax=$m;
    }
  }
  return($mmax);
}

# -----------------

my %o=();
my %state=();

# Test whether all commands defined to open/view files are
# reachable. If not, the user is warned...

sub test_commandes {
    my ($dont_warn)=@_;
    my @pasbon=();
    my @missing=();
    for my $c (grep { /_(viewer|editor|opener)$/ } keys(%o)) {
	my $nc=$o{$c};
	$nc =~ s/\s.*//;
	if(!commande_accessible($nc)) {
	    debug "Missing command [$c]: $nc";
	    push @missing,$c;
	    push @pasbon,$nc;
	}
    }
    if(@pasbon && !$dont_warn) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'warning','ok',
# TRANSLATORS: Message (first part) when some of the commands that are given in the preferences cannot be found.
			      __("Some commands allowing to open documents can't be found:")
			      ." ".join(", ",map { "<b>$_</b>"; } @pasbon).". "
# TRANSLATORS: Message (second part) when some of the commands that are given in the preferences cannot be found.
			      .__("Please check its correct spelling and install missing software.")." "
# TRANSLATORS: Message (third part) when some of the commands that are given in the preferences cannot be found. The %s will be replaced with the name of the menu entry "Preferences" and the name of the menu "Edit".
			      .sprintf(__"You can change used commands following <i>%s</i> from menu <i>%s</i>.",
# TRANSLATORS: "Preferences" menu
				       __"Preferences",
# TRANSLATORS: "Edit" menu
				       __"Edit"));
	$dialog->run;
	$dialog->destroy;
    }
    return(@missing);
}

# Creates general options directory if not present

if(! -d $o_dir) {
    mkdir($o_dir) or die "Error creating $o_dir : $!";

    # gets older verions (<=0.254) main configuration file and move it
    # to the new location

    if(-f $home_dir.'/.AMC.xml') {
	debug "Moving old configuration file";
	move($home_dir.'/.AMC.xml',$o_dir."/cf.default.xml");
    }
}

for my $o_sub (qw/plugins/) {
  mkdir("$o_dir/$o_sub") if(! -d "$o_dir/$o_sub");
}

#

sub sub_modif {
  my ($opts)=@_;
  my ($m,$mo)=($opts->{'_modifie'},$opts->{'_modifie_ok'});
  for my $k (keys %$opts) {
    if(ref($opts->{$k}) eq 'HASH') {
      $m.=','.$opts->{$k}->{'_modifie'} if($opts->{$k}->{'_modifie'});
      $mo=1 if($opts->{$k}->{'_modifie_ok'});
    }
  }
  return($m,$mo);
}

# Read/write options XML files

sub pref_xx_lit {
    my ($fichier)=@_;
    if((! -f $fichier) || -z $fichier) {
	return();
    } else {
	return(%{XMLin($fichier,SuppressEmpty => '')});
    }
}

sub pref_xx_ecrit {
    my ($data,$key,$fichier)=@_;
    if(open my $fh,">:encoding(utf-8)",$fichier) {
	XMLout($data,
	       "XMLDecl"=>'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
	       "RootName"=>$key,'NoAttr'=>1,
	       "OutputFile" => $fh,
	       );
	close $fh;
	return(0);
    } else {
	return(1);
    }
}

# Read/write running state

sub sauve_state {
    if($state{'_modifie'} || $state{'_modifie_ok'}) {
	debug "Saving state...";

	if(pref_xx_ecrit(\%state,'AMCState',$state_file)) {
	    my $dialog = Gtk2::MessageDialog
		->new($w{'main_window'},
		      'destroy-with-parent',
		      'error','ok',
# TRANSLATORS: Error writing one of the configuration files (global or project). The first %s will be replaced with the path of that file, and the second with the error text.
		      __"Error writing state file %s: %s",
		      $state_file,$!);
	    $dialog->run;
	    $dialog->destroy;
	} else {
	    $state{'_modifie'}=0;
	    $state{'_modifie_ok'}=0;
	}
    }
}

# annulation apprentissage

sub annule_apprentissage {
    my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'question','yes-no',
# Explains that some dialogs are shown only to learn AMC, only once by default (first part).
			  __("Several dialogs try to help you be at ease handling AMC.")." ".
# Explains that some dialogs are shown only to learn AMC, only once by default (second part). %s will be replaced with the text "Show this message again next time" that is written along the checkbox allowing the user to keep these learning message next time.
			  sprintf(__"Unless you tick the \"%s\" box, they are shown only once.",
# Explains that some dialogs are shown only to learn AMC, only once by default. This is the message shown along the checkbox allowing the user to keep these learning message next time.
				  __"Show this message again next time")." ".
# Explains that some dialogs are shown only to learn AMC, only once by default (third part). If you answer YES here, all these dialogs will be shown again.
			  __"Do you want to forgot which dialogs you have already seen and ask to show all of them next time they should appear ?"
			  );
    my $reponse=$dialog->run;
    $dialog->destroy;
    if($reponse eq 'yes') {
	debug "Clearing learning states...";
	$state{'apprentissage'}={};
	$state{'_modifie'}=1;
	sauve_state();
    }
}

# Read the state file

if(-r $state_file) {
    %state=pref_xx_lit($state_file);
    $state{'apprentissage'}={} if(!$state{'apprentissage'});
}

$state{'_modifie'}=0;
$state{'_modifie_ok'}=0;

# gets the last used profile

if(!$state{'profile'}) {
    $state{'profile'}='default';
    $state{'_modifie'}=1;
}

# sets new profile if given as a command argument

if($profile && $profile ne $state{'profile'}) {
    $state{'profile'}=$profile;
    $state{'_modifie'}=1;
}

sauve_state();

debug "Profile : $state{'profile'}";

$o_file=$o_dir."/cf.".$state{'profile'}.".xml";

# Read general options ...

if(-r $o_file) {
    %o=pref_xx_lit($o_file);
}

sub set_option_to_default {
    my ($key,$subkey,$force)=@_;
    if($subkey) {
	if($force || ! exists($o{$key}->{$subkey})) {
	    $o{$key}->{$subkey}=$o_defaut{$key}->{$subkey};
	    debug "New sub-global parameter : $key/$subkey = $o{$key}->{$subkey}";
	}
    } else {
	if($force || ! exists($o{$key})) {
	    # set to default
	    if(ref($o_defaut{$key}) eq 'ARRAY') {
		my ($type,@valeurs)=@{$o_defaut{$key}};
		if($type eq 'commande') {
		  UC: for my $c (@valeurs) {
		      if(commande_accessible($c)) {
			  $o{$key}=$c;
			  last UC;
		      }
		  }
		    if(!$o{$key}) {
			debug "No available command for option $key: using the first one";
			$o{$key}=$valeurs[0];
		    }
		} else {
		    debug "ERR: unknown option type : $type";
		}
	    } elsif(ref($o_defaut{$key}) eq 'HASH') {
		$o{$key}={%{$o_defaut{$key}}};
	    } else {
		$o{$key}=$o_defaut{$key};
		$o{$key}=$encodage_systeme if($key =~ /^encodage_/ && !$o{$key});
	    }
	    debug "New global parameter : $key = $o{$key}" if($o{$key});
	} else {
	    # already defined option: go with sub-options if any
	    if(ref($o_defaut{$key}) eq 'HASH') {
		for my $kk (keys %{$o_defaut{$key}}) {
		    set_option_to_default($key,$kk,$force);
		}
	    }
	}
    }
}

# sets undefined options to default value

for my $k (keys %o_defaut) {
    set_option_to_default($k);
}

# for unexisting commands options, see if we can find an available one
# from the default list

for my $k (test_commandes(1)) {
    set_option_to_default($k,'','FORCE');
}

# Clears modified flag for the options

$o{'_modifie'}=0;
$o{'_modifie_ok'}=0;

# some options were renamed to defaut_* between 0.226 and 0.227

for(qw/encodage_liste encodage_csv/) {
    if($o{"$_"} && ! $o{"defaut_$_"}) {
	$o{"defaut_$_"}=$o{"$_"};
	$o{'_modifie'}=1;
    }
}

# Replace old (pre 0.280) rep_modeles value with new one

if($o{'rep_modeles'} eq '/usr/share/doc/auto-multiple-choice/exemples') {
    $o{'rep_modeles'}=$o_defaut{'rep_modeles'};
    $o{'_modifie'}=1;
}

# Internal encoding _must_ be UTF-8, for XML::Writer (used by
# AMC::Gui::Association for example) to work
if($o{'encodage_interne'} ne 'UTF-8') {
    $o{'encodage_interne'}='UTF-8';
    $o{'_modifie'}=1;
}

# creates projets and models directories if needed (if not present,
# Edit/Parameters can be disrupted)

mkdir($o{'rep_projets'}) if(! -d $o{'rep_projets'});
mkdir($o{'rep_modeles'}) if(! -d $o{'rep_modeles'});

#############################################################################

my %projet=();

sub bon_encodage {
    my ($type)=@_;
    return($projet{'options'}->{"encodage_$type"}
	   || $o{"defaut_encodage_$type"}
	   || $o{"encodage_$type"}
	   || $o_defaut{"defaut_encodage_$type"}
	   || $o_defaut{"encodage_$type"}
	   || "UTF-8");
}

sub csv_build_0 {
  my ($k,@default)=@_;
  push @default,grep { $_ } map { s/^\s+//;s/\s+$//;$_; }
    split(/,+/,$o{'csv_'.$k.'_headers'});
  return("(".join("|",@default).")");
}

sub csv_build_name {
  return(csv_build_0('surname','nom','surname').' '
	 .csv_build_0('name','prenom','name'));
}

sub raccourcis {
    my ($proj)=@_;
    my %pathes=('%PROJETS'=>$o{'rep_projets'},
		'%HOME',$home_dir,
		''=>'%PROJETS',
	);
    $proj=$projet{'nom'} if(!$proj);
    if($proj) {
	$pathes{'%PROJET'}=$o{'rep_projets'}."/".$proj;
	$pathes{''}='%PROJET';
    }
    return(\%pathes);
}

sub absolu {
    my ($f,$proj)=@_;
    return($f) if(!defined($f));
    return(proj2abs(raccourcis($proj),$f));
}

sub relatif {
    my ($f,$proj)=@_;
    return($f) if(!defined($f));
    return(abs2proj(raccourcis($proj),$f));
}

sub id2file {
    my ($id,$prefix,$extension)=(@_);
    $id =~ s/\+//g;
    $id =~ s/\//-/g;
    return(absolu($projet{'options'}->{'cr'})."/$prefix-$id.$extension");
}

sub is_local {
    my ($f,$proj)=@_;
    my $prefix=$o{'rep_projets'}."/";
    $prefix .= $projet{'nom'}."/" if($proj);
    if(defined($f)) {
	return($f !~ /^[\/%]/
	       || $f =~ /^$prefix/
	       || $f =~ /[\%]PROJET\//);
    } else {
	return('');
    }
}

sub fich_options {
    my $nom=shift;
    return $o{'rep_projets'}."/$nom/options.xml";
}

sub moteur_latex {
    my $m=$projet{'options'}->{'moteur_latex_b'};
    $m=$o{'defaut_moteur_latex_b'} if(!$m);
    $m=$o_defaut{'defaut_moteur_latex_b'} if(!$m);
    return($m);
}

sub read_glade {
    my ($main_widget,@widgets)=@_;
    my $g=Gtk2::Builder->new();
    $g->set_translation_domain('auto-multiple-choice');
    $g->add_from_file($glade_base.$main_widget.".glade");
    for ($main_widget,@widgets) {
	$w{$_}=$g->get_object($_);
	if($w{$_}) {
	    $w{$_}->set_name($_) if(!/^(apropos)$/);
	} else {
	    debug "WARNING: Object $_ not found in $main_widget glade file.";
	}
    }
    $g->connect_signals(undef);
    return($g);
}

my $gui=read_glade('main_window',
		   qw/onglets_projet onglet_preparation preparation_etats
    but_question but_solution
    prepare_docs prepare_layout prepare_src
    state_layout state_src state_docs state_unrecognized state_marking state_assoc
    button_unrecognized button_show_missing
    edition_latex
    onglet_notation onglet_saisie onglet_reports
    log_general commande avancement annulation button_mep_warnings
    liste_filename liste_path liste_edit liste_setfile liste_refresh
    doc_menu menu_debug
    diag_tree state_capture
    maj_bareme regroupement_corriges
    groupe_model
    pref_assoc_c_assoc_code pref_assoc_c_liste_key
    export_c_format_export
    export_c_export_sort export_cb_export_include_abs
    config_export_modules standard_export_options
    notation_c_regroupement_type notation_cb_regroupement_compose
    pref_prep_s_nombre_copies pref_prep_c_filter
    /);

# Grid lines are not well-positioned in RTL environments, I don't know
# why... so I remove them.
if($w{'main_window'}->get_direction() eq 'rtl') {
    debug "RTL mode: removing vertical grids";
    for(qw/documents diag inconnu/) {
	my $w=$gui->get_object($_.'_tree');
	$w->set_grid_lines('horizontal') if($w);
    }
}

$w{'commande'}->hide();

sub debug_set {
    $debug=$w{'menu_debug'}->get_active;
    debug "DEBUG MODE : OFF" if(!$debug);
    set_debug($debug);
    if($debug) {
	debug "DEBUG MODE : ON";

	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
# TRANSLATORS: Messahe when switching to debugging mode.
		  __("Debugging mode.")." "
# TRANSLATORS: Messahe when switching to debugging mode. %s will be replaced with the path of the log file.
		  .sprintf(__"Debugging informations will be written in file %s.",AMC::Basic::debug_file()));
	$dialog->run;
	$dialog->destroy;
    }
}

$w{'menu_debug'}->set_active($debug);

# add doc list menu

my $docs_menu=Gtk2::Menu->new();

my @doc_langs=();

my $hdocdir=amc_specdir('doc/auto-multiple-choice')."/html/";
if(opendir(DOD,$hdocdir)) {
    push @doc_langs,map { s/auto-multiple-choice\.//;$_; } grep { /auto-multiple-choice\...(_..)?/ } readdir(DOD);
    closedir(DOD);
} else {
    debug("DOCUMENTATION : Can't open directory $hdocdir: $!");
}

# TRANSLATORS: One of the documentation languages.
my %ltext_loc=('French'=>__"French",
# TRANSLATORS: One of the documentation languages.
	       'English'=>__"English",
# TRANSLATORS: One of the documentation languages.
	       'Japanese'=>__"Japanese",
	       );

for my $l (@doc_langs) {
    my $ltext;
    $ltext=code2language($l);
    $ltext=$l if(! $ltext);
    $ltext=$ltext_loc{$ltext} if($ltext_loc{$ltext});
    my $m=Gtk2::ImageMenuItem->new_with_label($ltext);
    my $it=Gtk2::IconTheme->new();
    my ($taille,undef)=Gtk2::IconSize->lookup('menu');
    $it->prepend_search_path($hdocdir."auto-multiple-choice.$l");
    my $ii=$it->lookup_icon("flag",$taille ,"force-svg");
    if($ii) {
	$m->set_image(Gtk2::Image->new_from_pixbuf($it->load_icon("flag",$taille ,"force-svg")));
    }
    $m->signal_connect("activate",\&activate_doc,$l);
    $docs_menu->append($m);
}

$docs_menu->show_all();

$w{'doc_menu'}->set_submenu($docs_menu);

# make state entries with same background color as around...
$col=$w{'prepare_src'}->style()->bg('prelight');
for my $s (qw/normal insensitive/) {
  for my $k (qw/src docs layout capture marking unrecognized assoc/) {
    $w{'state_'.$k}->modify_base($s,$col);
  }
}

###

sub dialogue_apprentissage {
    my ($key,$type,$buttons,$force,@oo)=@_;
    my $resp='';
    $type='info' if(!$type);
    $buttons='ok' if(!$buttons);
    if($force || !$state{'apprentissage'}->{$key}) {
      my $garde;
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  $type,$buttons,
			  @oo);

      if(!$force) {
	$garde=Gtk2::CheckButton->new(__"Show this message again next time");
	$garde->set_active(0);
	$garde->can_focus(0);

	$dialog->get_content_area()->add($garde);
      }

      $dialog->show_all();

      $resp=$dialog->run;

      if(!($force || $garde->get_active())) {
	debug "Learning : $key";
	$state{'apprentissage'}->{$key}=1;
	$state{'_modifie'}=1;
	sauve_state();
      }

      $dialog->destroy;
    }
    return($resp);
}

### COPIES

my $copies_store = Gtk2::ListStore->new ('Glib::String');

### FILES FOR TEMPLATE

my $template_files_store = Gtk2::TreeStore->new ('Glib::String',
						 'Glib::String');

### Unrecognized scans

my $inconnu_store = Gtk2::ListStore->new ('Glib::String','Glib::String',
					  'Glib::String','Glib::String',
					  'Glib::String');

$inconnu_store->set_sort_column_id(INCONNU_TIME_N,GTK_SORT_ASCENDING);

### modele EMAILS

my $emails_store=Gtk2::ListStore->new ('Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				      );

### modele DIAGNOSTIQUE SAISIE

my $diag_store = Gtk2::ListStore->new ('Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String',
				       'Glib::String');

$w{'diag_tree'}->set_model($diag_store);

$renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of the column containing student/copy identifier in the table showing the results of data captures.
$column = Gtk2::TreeViewColumn->new_with_attributes (__"identifier",
						     $renderer,
						     text=> DIAG_ID,
						     'background'=> DIAG_ID_BACK);
$column->set_sort_column_id(DIAG_ID);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of the column containing data capture date/time in the table showing the results of data captures.
$column = Gtk2::TreeViewColumn->new_with_attributes (__"updated",
						     $renderer,
						     text=> DIAG_MAJ);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of the column containing Mean Square Error Distance (some kind of mean distance between the location of the four corner marks on the scan and the location where they should be if the scan was not distorted at all) in the table showing the results of data captures.
$column = Gtk2::TreeViewColumn->new_with_attributes (__"MSE",
						     $renderer,
						     'text'=> DIAG_EQM,
						     'background'=> DIAG_EQM_BACK);
$column->set_sort_column_id(DIAG_EQM);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of the column containing so-called "sensitivity" (an indicator telling the user if the darkness ratio of some boxes on the page are very near the threshold. A great value tells that some darkness ratios are very near the threshold, so that the capture is very sensitive to the threshold. A small value is a good thing) in the table showing the results of data captures.
$column = Gtk2::TreeViewColumn->new_with_attributes (__"sensitivity",
						     $renderer,
						     'text'=> DIAG_DELTA,
						     'background'=> DIAG_DELTA_BACK);
$column->set_sort_column_id(DIAG_DELTA);
$w{'diag_tree'}->append_column ($column);

$w{'diag_tree'}->get_selection->set_mode(GTK_SELECTION_MULTIPLE);

# rajouter a partir de Encode::Supported
# TRANSLATORS: for encodings
my $encodages=[{qw/inputenc latin1 iso ISO-8859-1/,'txt'=>'ISO-8859-1 ('.__("Western Europe").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin2 iso ISO-8859-2/,'txt'=>'ISO-8859-2 ('.__("Central Europe").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin3 iso ISO-8859-3/,'txt'=>'ISO-8859-3 ('.__("Southern Europe").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin4 iso ISO-8859-4/,'txt'=>'ISO-8859-4 ('.__("Northern Europe").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin5 iso ISO-8859-5/,'txt'=>'ISO-8859-5 ('.__("Cyrillic").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin9 iso ISO-8859-9/,'txt'=>'ISO-8859-9 ('.__("Turkish").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc latin10 iso ISO-8859-10/,'txt'=>'ISO-8859-10 ('.__("Northern").')'},
# TRANSLATORS: for encodings
	       {qw/inputenc utf8x iso UTF-8/,'txt'=>'UTF-8 ('.__("Unicode").')'},
	       {qw/inputenc cp1252 iso cp1252/,'txt'=>'Windows-1252',
		alias=>['Windows-1252','Windows']},
# TRANSLATORS: for encodings
	       {qw/inputenc applemac iso MacRoman/,'txt'=>'Macintosh '.__"Western Europe"},
# TRANSLATORS: for encodings
	       {qw/inputenc macce iso MacCentralEurRoman/,'txt'=>'Macintosh '.__"Central Europe"},
	       ];

sub get_enc {
    my ($txt)=@_;
    for my $e (@$encodages) {
	return($e) if($e->{'inputenc'} =~ /^$txt$/i ||
		      $e->{'iso'} =~ /^$txt$/i);
	if($e->{'alias'}) {
	    for my $a (@{$e->{'alias'}}) {
		return($e) if($a =~ /^$txt$/i);
	    }
	}
    }
    return('');
}

# TRANSLATORS: you can omit the [...] part, just here to explain context
my $cb_model_vide_key=cb_model(''=>__p"(none) [No primary key found in association list]");
# TRANSLATORS: you can omit the [...] part, just here to explain context
my $cb_model_vide_code=cb_model(''=>__p"(none) [No code found in LaTeX file]");

my %cb_stores=(
# TRANSLATORS: One option for decimal point: use a comma. This is a menu entry
    'delimiteur_decimal'=>cb_model(',',__", (comma)",
# TRANSLATORS: One option for decimal point: use a point. This is a menu entry.
				   '.',__". (dot)"),
# TRANSLATORS: One of the rounding method for marks. This is a menu entry.
    'note_arrondi'=>cb_model('inf',__"floor",
# TRANSLATORS: One of the rounding method for marks. This is a menu entry.
			     'normal',__"rounding",
# TRANSLATORS: One of the rounding method for marks. This is a menu entry.
			     'sup',__"ceiling"),
    'methode_impression'=>cb_model('CUPS','CUPS',
# TRANSLATORS: One of the printing methods: use a command (This is not the command name itself). This is a menu entry.
				   'commande',__"command",
# TRANSLATORS: One of the printing methods: print to files. This is a menu entry.
				   'file'=>__"to files"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
    'sides'=>cb_model('one-sided',__p("one sided [No two-sided printing]"),
# TRANSLATORS: One of the two-side printing types. This is a menu entry.
		      'two-sided-long-edge',__"long edge",
# TRANSLATORS: One of the two-side printing types. This is a menu entry.
		      'two-sided-short-edge',__"short edge"),
    'encodage_latex'=>cb_model(map { $_->{'iso'}=>$_->{'txt'} }
			       (@$encodages)),
# TRANSLATORS: you can omit the [...] part, just here to explain context
    'manuel_image_type'=>cb_model('ppm'=>__p("(none) [No transitional image type (direct processing)]"),
				  'xpm'=>'XPM',
				  'gif'=>'GIF'),
    'liste_key'=>$cb_model_vide_key,
    'assoc_code'=>$cb_model_vide_code,
    'format_export'=>cb_model(map { $_=>"AMC::Export::register::$_"->name() } (@export_modules)),
    'filter'=>cb_model(map { $_=>"AMC::Filter::register::$_"->name() } (@filter_modules)),
# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, do nothing more. This is a menu entry.
    'after_export'=>cb_model(""=>__"that's all",
# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, open the exported file. This is a menu entry.
			     "file"=>__"open the file",
# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, open the directory where the file is. This is a menu entry.
			     "dir"=>__"open the directory",
    ),
# TRANSLATORS: you can omit the [...] part, just here to explain context
    'annote_position'=>cb_model("none"=>__p("(none) [No annotation position (do not write anything)]"),
# TRANSLATORS: One of the possible location for questions scores on annotated completed answer sheet: in the margin. This is a menu entry.
				"marge"=>__"margin",
# TRANSLATORS: One of the possible location for questions scores on annotated completed answer sheet: near the boxes. This is a menu entry.
				"case"=>__"near boxes",
    ),
# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the student name. This is a menu entry.
    'export_sort'=>cb_model("n"=>__"name",
# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the student sheet number. This is a menu entry.
			    "i"=>__"sheet number",
# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the line where one can find this student in the students list file. This is a menu entry.
			    "l"=>__"line in students list",
# TRANSLATORS: you can omit the [...] part, just here to explain context
# One of the possible sorting criteria for students in the exported spreadsheet with scores: the student mark. This is a menu entry.
			    "m"=>__p("mark [student mark, for sorting]"),
			    ),
# TRANSLATORS: One of the possible way to group annotated answer sheets together to PDF files: make one PDF file per student, with all his pages. This is a menu entry.
    'regroupement_type'=>cb_model('STUDENTS'=>__"One file per student",
# TRANSLATORS: One of the possible way to group annotated answer sheets together to PDF files: make only one PDF with all students sheets. This is a menu entry.
				  'ALL'=>__"One file for all students",
    ),
# TRANLATORS: For which students do you want to annotate papers? This is a menu entry.
    'regroupement_copies'=>cb_model('ALL'=>__"All students",
# TRANLATORS: For which students do you want to annotate papers? This is a menu entry.
				    'SELECTED'=>__"Selected students",
				    ),
    'auto_capture_mode'=>cb_model(-1=>__"Please select...",
# TRANSLATORS: One of the ways exam was made: each student has a different answer sheet with a different copy number - no photocopy was made. This is a menu entry.
				  0=>__"Different answer sheets",
# TRANSLATORS: One of the ways exam was made: some students have the same exam subject, as some photocopies were made before distributing the subjects. This is a menu entry.
				  1=>__"Some answer sheets were photocopied"),
# TRANSLATORS: One of the ways to send mail: use sendmail command. This is a menu entry.
    'email_transport'=>cb_model('sendmail'=>__"sendmail",
# TRANSLATORS: One of the ways to send mail: use a SMTP server. This is a menu entry.
				'SMTP'=>__"SMTP"),
    );

# TRANSLATORS: One of the signs that can be drawn on annotated answer sheets to tell if boxes are to be ticked or not, and if they were detected as ticked or not.
my $symbole_type_cb=cb_model("none"=>__"nothing",
# TRANSLATORS: One of the signs that can be drawn on annotated answer sheets to tell if boxes are to be ticked or not, and if they were detected as ticked or not.
			     "circle"=>__"circle",
# TRANSLATORS: One of the signs that can be drawn on annotated answer sheets to tell if boxes are to be ticked or not, and if they were detected as ticked or not. Here, a cross.
			     "mark"=>__"mark",
# TRANSLATORS: One of the signs that can be drawn on annotated answer sheets to tell if boxes are to be ticked or not, and if they were detected as ticked or not. Here, the box outline.
			     "box"=>__"box",
			     );

for my $k (qw/0_0 0_1 1_0 1_1/) {
    $cb_stores{"symbole_".$k."_type"}=$symbole_type_cb;
}

$diag_store->set_sort_func(DIAG_EQM,\&sort_num,DIAG_EQM);
$diag_store->set_sort_func(DIAG_DELTA,\&sort_num,DIAG_DELTA);

# Add config GUI for export modules...

for my $m (@export_modules) {
  my $x="AMC::Export::register::$m"->build_config_gui(\%w,\%cb_stores);
  if($x) {
    $w{'config_export_module_'.$m}=$x;
    $w{'config_export_modules'}->pack_start($x,0,0,0);
  }
}

### export

sub maj_export {
    my $old_format=$projet{'options'}->{'format_export'};

    valide_options_for_domain('export','',@_);

    if($projet{'options'}->{'_modifie'} =~ /\bexport_sort\b/) {
      $projet{'_report'}->begin_transaction('SMch');
      $projet{'_report'}->variable('grouped_uptodate',-3);
      $projet{'_report'}->end_transaction('SMch');
    }

    debug "Format : ".$projet{'options'}->{'format_export'};

    for(@export_modules) {
      if($w{'config_export_module_'.$_}) {
	if($projet{'options'}->{'format_export'} eq $_) {
	  $w{'config_export_module_'.$_}->show;
	} else {
	  $w{'config_export_module_'.$_}->hide;
	}
      }
    }

    my %hide=("AMC::Export::register::".$projet{'options'}->{'format_export'})
      ->hide();
    for (qw/standard_export_options/) {
      if($hide{$_}) {
	$w{$_}->hide();
      } else {
	$w{$_}->show();
      }
    }
}

sub exporte {

  maj_export();

    my $format=$projet{'options'}->{'format_export'};
    my @options=();
    my $ext="AMC::Export::register::$format"->extension();
    if(!$ext) {
	$ext=lc($format);
    }
    my $type="AMC::Export::register::$format"->type();
    my $code=$projet{'options'}->{'code_examen'};
    $code=$projet{'nom'} if(!$code);
    my $output=absolu('%PROJET/exports/'.$code.$ext);
    my @needs_module=();

    my %ofc="AMC::Export::register::$format"
      ->options_from_config($projet{'options'},\%o,\%o_defaut);
    for(keys %ofc) {
      push @options,"--option-out",$_.'='.$ofc{$_};
    }
    push @needs_module,"AMC::Export::register::$format"->needs_module();

    if(@needs_module) {
	# teste si les modules necessaires sont disponibles

	my @manque=();

	for my $m (@needs_module) {
	    if(!check_install(module=>$m)) {
		push @manque,$m;
	    }
	}

	if(@manque) {
	    debug 'Exporting to '.$format.': Needs perl modules '.join(', ',@manque);

	    my $dialog = Gtk2::MessageDialog
	      ->new($w{'main_window'},
		    'destroy-with-parent',
		    'error','ok',
		    __("Exporting to '%s' needs some perl modules that are not installed: %s. Please install these modules or switch to another export format."),
		    "AMC::Export::register::$format"->name(),join(', ',@manque)
		   );
	    $dialog->run;
	    $dialog->destroy;

	    return();
	}
    }

    commande('commande'=>["auto-multiple-choice","export",
			  pack_args(
				    "--debug",debug_file(),
				    "--module",$format,
				    "--data",absolu($projet{'options'}->{'data'}),
				    "--useall",$projet{'options'}->{'export_include_abs'},
				    "--sort",$projet{'options'}->{'export_sort'},
				    "--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
				    "--noms-encodage",bon_encodage('liste'),
				    "--csv-build-name",csv_build_name(),
				    ($projet{'options'}->{'annote_rtl'} ? "--rtl" : "--no-rtl"),
				    "--output",$output,
				    @options
				   ),
			 ],
	     'texte'=>__"Exporting marks...",
	     'progres.id'=>'export',
	     'progres.pulse'=>0.01,
	     'fin'=>sub {
		 if(-f $output) {
		     if($projet{'options'}->{'after_export'} eq 'file') {
			 commande_parallele($o{$type.'_viewer'},$output)
			   if($o{$type.'_viewer'});
		     } elsif($projet{'options'}->{'after_export'} eq 'dir') {
			 view_dir(absolu('%PROJET/exports/'));
		     }
		 } else {
		     my $dialog = Gtk2::MessageDialog
			 ->new($w{'main_window'},
			       'destroy-with-parent',
			       'warning','ok',
			       __"Export to %s did not work: file not created...",$output);
		     $dialog->run;
		     $dialog->destroy;
		 }
	     }
	     );
}

## tri pour IDS

$diag_store->set_sort_func(DIAG_ID,\&sort_from_columns,
			   [{'type'=>'n','col'=>DIAG_ID_STUDENT},
			    {'type'=>'n','col'=>DIAG_ID_COPY},
			    {'type'=>'n','col'=>DIAG_ID_PAGE},
			   ]);
$diag_store->set_sort_column_id(DIAG_ID,GTK_SORT_ASCENDING);

## menu contextuel sur liste diagnostique -> visualisation zoom/page

# TRANSLATORS: One of the popup menu that appears when right-clicking on a page in the data capture diagnosis table. Choosing this entry, an image will be opened to see where the corner marks were detected.
my %diag_menu=(page=>{text=>__"page adjustment",icon=>'gtk-zoom-fit'},
# TRANSLATORS: One of the popup menu that appears when right-clicking on a page in the data capture diagnosis table. Choosing this entry, a window will be opened were the user can see all boxes on the scans and how they were filled by the students, and correct detection of ticked-or-not if needed.
	       zoom=>{text=>__"boxes zooms",icon=>'gtk-zoom-in'},
	       );

sub zooms_display {
    my ($student,$page,$copy,$forget_it)=@_;

    debug "Zooms view for ".pageids_string($student,$page,$copy)."...";
    my $zd=absolu('%PROJET/cr/zooms');
    debug "Zooms directory $zd";
    if($w{'zooms_window'} &&
       $w{'zooms_window'}->actif) {
	$w{'zooms_window'}->page([$student,$page,$copy],$zd,$forget_it);
    } elsif(!$forget_it) {
	$w{'zooms_window'}=AMC::Gui::Zooms::new('seuil'=>$projet{'options'}->{'seuil'},
						'n_cols'=>$o{'zooms_ncols'},
						'zooms_dir'=>$zd,
						'page_id'=>[$student,$page,$copy],
						'size-prefs',\%o,
						'encodage_interne'=>$o{'encodage_interne'},
						'data'=>$projet{'_capture'},
						'cr-dir'=>absolu($projet{'options'}->{'cr'}),
	    );
    }
}

sub zooms_line_base {
  my ($forget_it)=@_;
  my @selected=$w{'diag_tree'}->get_selection->get_selected_rows;
  if(@selected) {
    my $iter=$diag_store->get_iter($selected[0]);
    my $id=$diag_store->get($iter,DIAG_ID);
    zooms_display((map { $diag_store->get($iter,$_) } (DIAG_ID_STUDENT,
						       DIAG_ID_PAGE,
						       DIAG_ID_COPY)
		  ),$forget_it);
  }
}

sub zooms_line { zooms_line_base(1); }
sub zooms_line_open { zooms_line_base(0); }

sub layout_line {
  my @selected=$w{'diag_tree'}->get_selection->get_selected_rows;
  for my $s (@selected) {
    my $iter=$diag_store->get_iter($s);
    my @id=map { $diag_store->get($iter,$_); } 
      (DIAG_ID_STUDENT,DIAG_ID_PAGE,DIAG_ID_COPY);
    $projet{'_capture'}->begin_read_transaction('Layl');
    my $f=absolu($projet{'options'}->{'cr'}).'/'
      .$projet{'_capture'}->get_layout_image(@id);
    $projet{'_capture'}->end_transaction('Layl');

    commande_parallele($o{'img_viewer'},$f) if(-f $f);
  }
}

sub delete_line {
  my @selected=$w{'diag_tree'}->get_selection->get_selected_rows;
  my $f;
  if(@selected) {
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'question','yes-no',
			sprintf((__"You requested to delete all data capture results for %d page(s)"),1+$#selected)."\n"
			.'<b>'.(__"All data and image files related to these pages will be deleted.")."</b>\n"
			.(__"Do you really want to continue?")
		       );
    my $reponse=$dialog->run;
    $dialog->destroy;
    if($reponse eq 'yes') {
      my @iters=();
      $projet{'_capture'}->begin_transaction('rmAN');
      for my $s (@selected) {
	my $iter=$diag_store->get_iter($s);
	my @id=map { $diag_store->get($iter,$_); } 
	  (DIAG_ID_STUDENT,DIAG_ID_PAGE,DIAG_ID_COPY);
	debug "Removing data capture for ".pageids_string(@id);
	#
	# 1) get image files generated, and remove them
	#
	my $crdir=absolu($projet{'options'}->{'cr'});
	my @files=();
	#
	# scan file
	push @files,absolu($projet{'_capture'}->get_scan_page(@id));
	#
	# layout image, in cr directory
	push @files,$crdir.'/'
	  .$projet{'_capture'}->get_layout_image(@id);
	#
	# annotated scan
	push @files,$crdir.'/corrections/jpg/'
	  .$projet{'_capture'}->get_annotated_page(@id);
	#
	# zooms
	push @files,map { $crdir.'/zooms/'.$_ } 
	  ($projet{'_capture'}->get_zones_images(@id,ZONE_BOX));
	#
	for (@files) {
	  if (-f $_) {
	    debug "Removing $_";
	    unlink($_);
	  }
	}
	#
	# 2) remove data from database
	#
	$projet{'_capture'}->delete_page_data(@id);

	push @iters,$iter;
      }

      for(@iters) { $diag_store->remove($_); }
      update_analysis_summary();
      $projet{'_capture'}->end_transaction('rmAN');
    }
  }
}

$w{'diag_tree'}->signal_connect('button_release_event' =>
    sub {
	my ($self, $event) = @_;
	return 0 unless $event->button == 3;
	my ($path, $column, $cell_x, $cell_y) =
	    $w{'diag_tree'}->get_path_at_pos ($event->x, $event->y);
	if ($path) {
	    my $iter=$diag_store->get_iter($path);
	    my $id=[map { $diag_store->get($iter,$_) } (DIAG_ID_STUDENT,
							DIAG_ID_PAGE,
							DIAG_ID_COPY)];

	    my $menu = Gtk2::Menu->new;
	    my $c=0;
	    my @actions=('page');

	    # new zooms viewer

	    $projet{'_capture'}->begin_read_transaction('ZnIm');
	    my @bi=grep { -f absolu('%PROJET/cr/zooms')."/".$_ }
	      $projet{'_capture'}->zone_images($id->[0],$id->[2],ZONE_BOX);
	    $projet{'_capture'}->end_transaction('ZnIm');

	    if(@bi) {
		$c++;
		my $item = Gtk2::ImageMenuItem->new($diag_menu{'zoom'}->{text});
		$item->set_image(Gtk2::Image->new_from_icon_name($diag_menu{'zoom'}->{icon},'menu'));
		$menu->append ($item);
		$item->show;
		$item->signal_connect (activate => sub {
		    my (undef, $sortkey) = @_;
		    zooms_display(@$id);
				       }, $_);
	    } else {
		push  @actions,'zoom';
	    }

	    # page viewer and old zooms viewer

	    foreach $a (@actions) {
	      my $f;
	      if($a eq 'page') {
		$projet{'_capture'}->begin_read_transaction('gLIm');
		$f=absolu($projet{'options'}->{'cr'}).'/'
		  .$projet{'_capture'}->get_layout_image(@$id);
		$projet{'_capture'}->end_transaction('gLIm');
	      } else {
		$f=id2file($id,$a,'jpg');
	      }
	      if(-f $f) {
		$c++;
		my $item = Gtk2::ImageMenuItem->new($diag_menu{$a}->{text});
		$item->set_image(Gtk2::Image->new_from_icon_name($diag_menu{$a}->{icon},'menu'));
		$menu->append ($item);
		$item->show;
		$item->signal_connect (activate => sub {
					 my (undef, $sortkey) = @_;
					 debug "Looking at $f...";
					 commande_parallele($o{'img_viewer'},$f);
				       }, $_);
	      }
	    }
	    $menu->popup (undef, undef, undef, undef,
			  $event->button, $event->time) if($c>0);
	    return 1; # stop propagation!

	}
    });

### Appel a des commandes externes -- log, annulation

my %les_commandes=();
my $cmd_id=0;

sub commande {
    my (@opts)=@_;
    $cmd_id++;

    my $c=AMC::Gui::Commande::new('avancement'=>$w{'avancement'},
				  'log'=>$w{'log_general'},
				  'finw'=>sub {
				      my $c=shift;
				      $w{'onglets_projet'}->set_sensitive(1);
				      $w{'commande'}->hide();
				      delete $les_commandes{$c->{'_cmdid'}};
				  },
				  @opts);

    $c->{'_cmdid'}=$cmd_id;
    $les_commandes{$cmd_id}=$c;

    $w{'onglets_projet'}->set_sensitive(0);
    $w{'commande'}->show();

    $c->open();
}

sub commande_annule {
    for (keys %les_commandes) { $les_commandes{$_}->quitte(); }
}

sub commande_parallele {
    my (@c)=(@_);
    if(commande_accessible($c[0])) {
	my $pid=fork();
	if($pid==0) {
	    debug "Command // [$$] : ".join(" ",@c);
	    exec(@c) ||
		debug "Exec $$ : error";
	    exit(0);
	}
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      sprintf(__"Following command could not be run: <b>%s</b>, perhaps due to a poor configuration?",$c[0]));
	$dialog->run;
	$dialog->destroy;

    }
}

### Actions des menus

my $proj_store;

sub projet_nouveau {
    liste_des_projets('cree'=>1);
}

sub projet_charge {
    liste_des_projets();
}

sub projet_gestion {
    liste_des_projets('gestion'=>1);
}

sub liste_des_projets {
    my %oo=(@_);
    my @projs;

    mkdir($o{'rep_projets'}) if(-d $o{'rep_projets'});

    # construit la liste des projets existants

    if(-d $o{'rep_projets'}) {
	opendir(DIR, $o{'rep_projets'})
	    || die "Error opening directory ".$o{'rep_projets'}." : $!";
	my @f=map { decode("utf-8",$_); } readdir(DIR);
	debug "F:".join(',',map { $_.":".(-d $o{'rep_projets'}."/".$_) } @f);

	@projs = grep { ! /^\./ && -d $o{'rep_projets'}."/".$_ } @f;
	closedir DIR;
	debug "[".$o{'rep_projets'}."] P:".join(',',@projs);
    }

    if($#projs>=0 || $oo{'cree'}) {

	# fenetre pour demander le nom du projet

	my $gp=read_glade('choix_projet',
			  qw/label_etat label_action
            choix_projets_liste
	    projet_bouton_ouverture projet_bouton_creation
	    projet_bouton_supprime projet_bouton_annule
	    projet_bouton_annule_label projet_bouton_renomme
	    projet_bouton_mv_yes projet_bouton_mv_no
	    projet_nom projet_nouveau_syntaxe projet_nouveau/);

	if($oo{'cree'}) {
	    $w{'projet_nouveau'}->show();
	    $w{'projet_bouton_creation'}->show();
	    $w{'projet_bouton_ouverture'}->hide();

	    $w{'label_etat'}->set_text(__"Existing projects:");

	    $w{'choix_projet'}->set_focus($w{'projet_nom'});
	    $w{'projet_nom_style'} = $w{'projet_nom'}->get_modifier_style->copy;

# TRANSLATORS: Window title when creating a new project.
	    $w{'choix_projet'}->set_title(__"New AMC project");
	}


	if($oo{'gestion'}) {
	    $w{'label_etat'}->set_text(__"Projects management:");
	    $w{'label_action'}->set_markup(__"Change project name:");
	    $w{'projet_bouton_ouverture'}->hide();
	    for (qw/supprime renomme/) {
		$w{'projet_bouton_'.$_}->show();
	    }
	    $w{'projet_bouton_annule_label'}->set_text(__"Back");

# TRANSLATORS: Window title when managing projects.
	    $w{'choix_projet'}->set_title(__"AMC projects management");
	}

	# mise a jour liste des projets dans la fenetre

	$proj_store = Gtk2::ListStore->new ('Glib::String',
					    'Gtk2::Gdk::Pixbuf');

	$w{'choix_projets_liste'}->set_model($proj_store);

	$w{'choix_projets_liste'}->set_text_column(PROJ_NOM);
	$w{'choix_projets_liste'}->set_pixbuf_column(PROJ_ICO);

	my ($taille,undef)=Gtk2::IconSize->lookup('menu');
        my $pb = Gtk2::IconTheme->get_default->load_icon("auto-multiple-choice",$taille ,"force-svg");
	my $pb_rep = Gtk2::IconTheme->get_default->load_icon("gtk-no",$taille ,"force-svg");
	$pb=$w{'main_window'}->render_icon ('gtk-open', 'menu') if(!$pb);

	for (sort { $a cmp $b } @projs) {
	    $proj_store->set($proj_store->append,
			     PROJ_NOM,$_,
			     PROJ_ICO,
			     (-f fich_options($_) ?
			       $pb : $pb_rep ));
	}

	# attendons l'action de l'utilisateur (fonctions projet_charge_*)...

	$w{'choix_projet'}->set_keep_above(1);

    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  __"You don't have any MC project in directory %s!",$o{'rep_projets'});
	$dialog->run;
	$dialog->destroy;

    }
}

sub projet_gestion_check {
    # lequel ?

    my $sel=$w{'choix_projets_liste'}->get_selected_items();
    my $iter;
    my $proj;

    if($sel) {
	$iter=$proj_store->get_iter($sel);
	$proj=$proj_store->get($iter,PROJ_NOM) if($iter);
    }

    return('','') if(!$proj);

    # est-ce le projet en cours ?

    if($projet{'nom'} && $proj eq $projet{'nom'}) {
	$w{'choix_projet'}->set_keep_above(0);
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  __"You can't change project %s since it's open.",$proj);
	$dialog->run;
	$dialog->destroy;
	$w{'choix_projet'}->set_keep_above(1);
	$proj='';
    }

    return($proj,$iter);
}

my $nom_original='';
my $nom_original_iter='';

sub projet_liste_renomme {
    my ($proj,$iter)=projet_gestion_check();
    return if(!$proj);

    # ouverture zone :
    $w{'projet_nouveau'}->show();
    $w{'projet_nom'}->set_text($proj);

    $nom_original=$proj;
    $nom_original_iter=$iter;

    # boutons...
    for (qw/annule renomme supprime/) {
	$w{'projet_bouton_'.$_}->hide();
    }
    for (qw/mv_no mv_yes/) {
	$w{'projet_bouton_'.$_}->show();
    }
}

sub projet_renomme_fin {
    # fermeture zone :
    $w{'projet_nouveau'}->hide();

    # boutons...
    for (qw/annule renomme supprime/) {
	$w{'projet_bouton_'.$_}->show();
    }
    for (qw/mv_no mv_yes/) {
	$w{'projet_bouton_'.$_}->hide();
    }
}

sub projet_mv_yes {
    projet_renomme_fin();

    my $nom_nouveau=$w{'projet_nom'}->get_text();

    return if($nom_nouveau eq $nom_original || !$nom_nouveau);

    if($o{'rep_projets'}) {
	my $dir_original=$o{'rep_projets'}."/".$nom_original;
	if(-d $dir_original) {
	    my $dir_nouveau=$o{'rep_projets'}."/".$nom_nouveau;
	    if(-d $dir_nouveau) {
		$w{'choix_projet'}->set_keep_above(0);
		my $dialog = Gtk2::MessageDialog
		    ->new_with_markup($w{'main_window'},
				      'destroy-with-parent',
				      'error','ok',
# TRANSLATORS: Message when you want to create an AMC project with name xxx, but there already exists a directory in the projects directory with this name!
				      sprintf(__("Directory <i>%s</i> already exists, so you can't choose this name."),$dir_nouveau));
		$dialog->run;
		$dialog->destroy;
		$w{'choix_projet'}->set_keep_above(1);

		return;
	    } else {
		# OK

		move($dir_original,$dir_nouveau);

		$proj_store->set($nom_original_iter,
				 PROJ_NOM,$nom_nouveau,
				 );
	    }
	} else {
	    debug "No original directory";
	}
    } else {
	debug "No projects directory";
    }
}

sub projet_mv_no {
    projet_renomme_fin();
}

sub projet_liste_supprime {
    my ($proj,$iter)=projet_gestion_check();
    return if(!$proj);

    # on demande confirmation...
    $w{'choix_projet'}->set_keep_above(0);
    my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'warning','ok-cancel',
			  sprintf(__("You asked to remove project <b>%s</b>.")." "
				  .__("This will permanently erase all the files of this project, including the source file as well as all the files you put in the directory of this project, as the scans for example.")." "
				  .__("Is this really what you want?"),$proj));
    my $reponse=$dialog->run;
    $dialog->destroy;
    $w{'choix_projet'}->set_keep_above(1);

    if($reponse ne 'ok') {
	return;
    }

    debug "Removing project $proj !";

    $proj_store->remove($iter);

    # suppression effective des fichiers...

    if($o{'rep_projets'}) {
	my $dir=$o{'rep_projets'}."/".$proj;
	if(-d $dir) {
	    remove_tree($dir,{'verbose'=>0,'safe'=>1,'keep_root'=>0});
	} else {
	    debug "No directory $dir";
	}
    } else {
	debug "No projects directory";
    }
}

sub projet_charge_ok {

    # ouverture projet deja existant

    my $sel=$w{'choix_projets_liste'}->get_selected_items();
    my $proj;

    if($sel) {
	$proj=$proj_store->get($proj_store->get_iter($sel),PROJ_NOM);
    }

    $w{'choix_projet'}->destroy();

    if($proj) {
	my $reponse='yes';
	if(! -f fich_options($proj)) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'warning','yes-no',
				  sprintf(__("You selected directory <b>%s</b> as a project to open.")." "
					  .__("However, this directory does not seem to contain a project. Dou you still want to try?"),$proj));
	    $reponse=$dialog->run;
	    $dialog->destroy;
	}
	projet_ouvre($proj) if($reponse eq 'yes');
    }
}

sub restricted_check {
    my ($text,$style,$warning,$chars)=@_;
    my $nom=$text->get_text();
    if($nom =~ s/[^$chars]//g) {
	$text->set_text($nom);
	$warning->show();

	for(qw/normal active/) {
	    $text->modify_base($_,Gtk2::Gdk::Color->parse('#FFC0C0'));
	}
	Glib::Timeout->add (500, sub {
	    $text->modify_style($style);
	    return 0;
	});
    }
}

sub projet_nom_verif {
    restricted_check($w{'projet_nom'},$w{'projet_nom_style'},$w{'projet_nouveau_syntaxe'},"a-zA-Z0-9._+:-");
}

sub projet_charge_nouveau {

    # creation nouveau projet

    my $proj=$w{'projet_nom'}->get_text();
    $w{'choix_projet'}->destroy();

    # existe deja ?

    if(-e $o{'rep_projets'}."/$proj") {

	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      sprintf(__("The name <b>%s</b> is already used in the projects directory.")." "
				      .__"You must choose another name to create a project.",$proj));
	$dialog->run;
	$dialog->destroy;


    } else {

	if(projet_ouvre($proj,1)) {
	    projet_sauve();
	}

    }
}

sub projet_charge_non {
    $w{'choix_projet'}->destroy();
}

sub projet_sauve {
    debug "Saving project...";
    my $of=fich_options($projet{'nom'});
    my $po={%{$projet{'options'}}};

    for(qw/listeetudiants/) {
	$po->{$_}=relatif($po->{$_});
    }

    if(pref_xx_ecrit($po,'projetAMC',$of)) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  __"Error writing to options file %s: %s",$of,$!);
	$dialog->run;
	$dialog->destroy;
    } else {
	$projet{'options'}->{'_modifie'}=0;
	$projet{'options'}->{'_modifie_ok'}=0;
    }
}

sub projet_check_and_save {
    if($projet{'nom'}) {
	valide_options_notation();
	my ($m,$mo)=sub_modif($projet{'options'});
	if($m || $mo) {
	    projet_sauve();
	}
    }
}

### Actions des boutons de la partie DOCUMENTS

sub format_markup {
  my ($t)=@_;
  $t =~ s/\&/\&amp;/g;
  return($t);
}

sub mini {($_[0]<$_[1] ? $_[0] : $_[1])}

my %component_name=('latex_packages'=>__("LaTeX packages:"),
		    'commands'=>__("Commands:"),
		    'fonts'=>__("Fonts:"),
		    );

sub set_project_option {
  my ($name,$value)=@_;
  my $old=$projet{'options'}->{$name};
  $projet{'options'}->{$name}=$value;
  $projet{'options'}->{'_modifie'}.=','.$name if($value ne $old);
}


sub doc_maj {
    my $sur=0;
    if($projet{'_capture'}->n_pages_transaction()>0) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'warning','ok-cancel',
			      __("Papers analysis was already made on the basis of the current working documents.")." "
			      .__("You already made the examination on the basis of these documents.")." "
			      .__("If you modify working documents, you will not be capable any more of analyzing the papers you have already distributed!")." "
			      .__("Do you wish to continue?")." "
			      .__("Click on Validate to erase the former layouts and update working documents, or on Cancel to cancel this operation.")." "
			      ."<b>".__("To allow the use of an already printed question, cancel!")."</b>");
	my $reponse=$dialog->run;
	$dialog->destroy;

	if($reponse eq 'cancel') {
	    return(0);
	}

	$sur=1;
    }

    # deja des MEP fabriquees ?
    $projet{_layout}->begin_transaction('DMAJ');
    my $pc=$projet{_layout}->pages_count;
    $projet{_layout}->end_transaction('DMAJ');
    if($pc > 0) {
	if(!$sur) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'question','ok-cancel',
				  __("Layouts are already calculated for the current documents.")." "
				  .__("Updating working documents, the layouts will become obsolete and will thus be erased.")." "
				  .__("Do you wish to continue?")." "
				  .__("Click on Validate to erase the former layouts and update working documents, or on Cancel to cancel this operation.")
				  ." <b>".__("To allow the use of an already printed question, cancel!")."</b>");
	    my $reponse=$dialog->run;
	    $dialog->destroy;

	    if($reponse eq 'cancel') {
		return(0);
	    }
	}

	clear_processing('mep:');
    }

    # new layout document : XY (from LaTeX)

    if($projet{'options'}->{'docs'}->[2] =~ /\.pdf$/) {
	$projet{'options'}->{'docs'}->[2]=$projet_defaut{'docs'}->[2];
	$projet{'options'}->{'_modifie'}=1;
    }

    # check for filter dependencies

    my $filter_register=("AMC::Filter::register::".$projet{'options'}->{'filter'})
      ->new();

    my $check=$filter_register->check_dependencies();

    if(!$check->{'ok'}) {
      my $message=sprintf(__("To handle properly <i>%s</i> files, AMC needs the following components, that are currently missing:"),$filter_register->name())."\n";
      for my $k (qw/latex_packages commands fonts/) {
	if(@{$check->{$k}}) {
	  $message .= "<b>".$component_name{$k}."</b> ";
	  if($k eq 'fonts') {
	    $message.=join(', ',map { @{$_->{'family'}} } @{$check->{$k}});
	  } else {
	    $message.=join(', ',@{$check->{$k}});
	  }
	  $message.="\n";
	}
      }
      $message.=__("Install these components on your system and try again.");

      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',$message);
      $dialog->run;
      $dialog->destroy;

      return(0);
    }

    # set options from filter:

    if($projet{'options'}->{'filter'}) {
      $filter_register->set_oo($projet{'options'});
      $filter_register->configure();
    }

    #
    commande('commande'=>["auto-multiple-choice","prepare",
			  "--with",moteur_latex(),
			  "--filter",$projet{'options'}->{'filter'},
			  "--filtered-source",absolu($projet{'options'}->{'filtered_source'}),
			  "--debug",debug_file(),
			  "--out-sujet",absolu($projet{'options'}->{'docs'}->[0]),
			  "--out-corrige",absolu($projet{'options'}->{'docs'}->[1]),
			  "--out-calage",absolu($projet{'options'}->{'docs'}->[2]),
			  "--mode","s",
			  "--n-copies",$projet{'options'}->{'nombre_copies'},
			  absolu($projet{'options'}->{'texsrc'}),
			  "--prefix",absolu('%PROJET/'),
			  "--latex-stdout",
			  ],
	     'signal'=>2,
	     'texte'=>__"Documents update...",
	     'progres.id'=>'MAJ',
	     'progres.pulse'=>0.01,
	     'fin'=>sub {
		 my $c=shift;
		 my @err=$c->erreurs();
		 if(@err) {
		   my $message=__("Errors while processing the source file.")
		     ." "
		       .__("You have to correct the source file and re-run documents update.")." "
# TRANSLATORS: Here, %s will be replaced with the translation of "Command output details", and refers to the small expandable part at the bottom of AMC main window, where one can see the output of the commands lauched by AMC.
			 .sprintf(__("See the processing log in '%s' below."),
# TRANSLATORS: Title of the small expandable part at the bottom of AMC main window, where one can see the output of the commands lauched by AMC.
				  __"Command output details");
		   $message.=" ".__("Use LaTeX editor or latex command for a precise diagnosis.") if($projet{'options'}->{'filter'} eq 'latex');
		   $message.="\n\n".join("\n",map { format_markup($_) } (@err[0..mini(9,$#err)])).($#err>9 ? "\n\n<i>(".__("Only first ten errors written").")</i>": "");

		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'error','ok',
					   $message);
		     $dialog->run;
		     $dialog->destroy;
		 } else {
		     # verif que tout y est

		     my $ok=1;
		     for(0..2) {
			 $ok=0 if(! -f absolu($projet{'options'}->{'docs'}->[$_]));
		     }
		     if($ok) {

		       # set project option from filter requests

		       my %vars=$c->variables;
		       for my $k (keys %vars) {
			 if($k =~ /^project:(.*)/) {
			   set_project_option($1,$vars{$k});
			 }
		       }

		       # success message

		       dialogue_apprentissage('MAJ_DOCS_OK','','',0,
					      __("Working documents successfully generated.")." "
# TRANSLATORS: Here, "them" refers to the working documents.
					      .__("You can take a look at them double-clicking on the list.")." "
# TRANSLATORS: Here, "they" refers to the working documents.
					      .__("If they are correct, proceed to layouts detection..."));
		     }
		 }

		 my $ap=($c->variable('ensemble') ? 'case' : 'marge');
		 $projet{'options'}->{'_modifie'}=1
		     if($projet{'options'}->{'annote_position'} ne $ap);
		 $projet{'options'}->{'annote_position'}=$ap;

		 my $ensemble=$c->variable('ensemble') && !$c->variable('outsidebox');
		 if(($ensemble  || $c->variable('insidebox'))
		    && $projet{'options'}->{'seuil'}<0.4) {
		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'question','yes-no',
					   sprintf(($ensemble ?
						    __("Your question has a separate answers page.")." "
						    .__("In this case, letters are shown inside boxes.") :
						   __("Your question is set to present labels inside the boxes to be ticked."))
						   ." "
# TRANSLATORS: Here, %s will be replaced with the translation of "darkness threshold".
						   .__("For better ticking detection, ask students to fill out completely boxes, and choose parameter \"%s\" around 0.5 for this project.")." "
						   .__("At the moment, this parameter is set to %.02f.")." "
						   .__("Would you like to set it to 0.5?")
# TRANSLATORS: This parameter is the ratio of dark pixels number over total pixels number inside box above which a box is considered to be ticked.
						   ,__"darkness threshold",
						   $projet{'options'}->{'seuil'}) );
		     my $reponse=$dialog->run;
		     $dialog->destroy;
		     if($reponse eq 'yes') {
			 $projet{'options'}->{'seuil'}=0.5;
			 $projet{'options'}->{'_modifie'}=1;
		     }
		 }
		 detecte_documents();
	     });

}

sub filter_details {
  my $gd=read_glade('filter_details',
		    qw/filter_text/);
  debug "Filter details: conf->details GUI";
  transmet_pref($gd,'filter_details',$projet{'options'});
  my $r=$w{'filter_details'}->run();
  if($r == 10) {
    my %oo=('filter'=>'');
    debug "Filter details: new value->local";
    reprend_pref('filter_details',\%oo);
    $w{'filter_details'}->destroy;
    debug "Filter details: local->main GUI";
    transmet_pref($gui,'pref_prep',\%oo);
  } else {
    $w{'filter_details'}->destroy;
  }
}

sub filter_details_update {
  my %oo=('filter'=>'');
  reprend_pref('filter_details',\%oo);
  my $b=$w{'filter_text'}->get_buffer;
  if($oo{'filter'}) {
    $b->set_text(("AMC::Filter::register::".$oo{'filter'})->description);
  } else {
    $b->set_text('');
  }
}

my $cups;
my $g_imprime;

sub nonnul {
    my $s=shift;
    $s =~ s/\000//g;
    return($s);
}

sub autre_imprimante {
    my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
    debug "Choix imprimante $i";
    my $ppd=$cups->getPPD($i);

    my %alias=();
    my %trouve=();

    debug "Looking for staple opton...";

  CHOIX: for my $i (qw/StapleLocation/) {
      my $oi=$ppd->getOption($i);

      $alias{$i}='agrafe';

      if(%$oi) {
	  my $k=nonnul($oi->{'keyword'});
	  debug "$i -> KEYWORD $k";
	  my $ok=$o{'options_impression'}->{$k};
	  my @possibilites=(map { (nonnul($_->{'choice'}),
				   nonnul($_->{'text'})) }
			    (@{$oi->{'choices'}}));
	  my %ph=(@possibilites);
	  $cb_stores{'agrafe'}=cb_model(@possibilites);
	  $o{'options_impression'}->{$k}=nonnul($oi->{'defchoice'})
	      if(!$ok || !$ph{$ok});

	  $alias{$k}='agrafe';
	  $trouve{'agrafe'}=$k;

	  last CHOIX;
      }
  }
    if(!$trouve{'agrafe'}) {
	debug "No possible staple";

# TRANSLATORS: There is a menu for choosing stapling or not from the printer. When stapling is not available on the chosen printer, this is the only offered choice.
	$cb_stores{'agrafe'}=cb_model(''=>__"(not supported)");
	$w{'imp_c_agrafe'}->set_model($cb_stores{'agrafe'});
    }

    transmet_pref($g_imprime,'imp',$o{'options_impression'},
		  \%alias);
}

sub sujet_impressions {

    if(! -f absolu($projet{'options'}->{'docs'}->[0])) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
# TRANSLATORS: Message when the user required printing the question paper, but it is not present (probably the working documents have not been properly generated).
			      __"You don't have any question to print: please check your source file and update working documents first.");
	$dialog->run;
	$dialog->destroy;

	return();
    }

    $projet{'_layout'}->begin_read_transaction('PGCN');
    my $c=$projet{'_layout'}->pages_count;
    $projet{'_layout'}->end_transaction('PGCN');
    if($c==0) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
# TRANSLATORS: Message when AMC does not know about the subject pages that has been generated. Usualy this means that the layout computation step has not been made.
			      __("Question's pages are not detected.")." "
			      .__"Perhaps you forgot to compute layouts?");
	$dialog->run;
	$dialog->destroy;

	return();
    }

    debug "Choosing pages to print...";

    if($o{'methode_impression'} eq 'CUPS') {
	# teste si le paquet Net::CUPS est disponible

	my @manque=();

	for my $m ("Net::CUPS","Net::CUPS::PPD") {
	    if(check_install(module=>$m)) {
		load($m);
	    } else {
		push @manque,$m;
	    }
	}

	if(@manque) {
	    debug 'Printing with CUPS: Needs perl modules '.join(', ',@manque);

	    my $dialog = Gtk2::MessageDialog
		->new($w{'main_window'},
		      'destroy-with-parent',
		      'error','ok',
		      __("Printing with method '%s' needs some perl modules that are not installed: %s. Please install these modules or switch to another printing method."),
		      __"CUPS",join(', ',@manque)
		      );
	    $dialog->run;
	    $dialog->destroy;

	    return();
	}

	# verifie aussi qu'il y a au moins une imprimante configuree

	my $sc=Net::CUPS->new();
	my @pl = $sc->getDestinations();

	if(!@pl) {
	    my $dialog = Gtk2::MessageDialog
		->new($w{'main_window'},
		      'destroy-with-parent',
		      'error','ok',
		      __("You chose printing method '%s' but there are no configured printer in CUPS. Please configure some printer or switch to another printing method."),
		      __"CUPS"
		      );
	    $dialog->run;
	    $dialog->destroy;

	    return();
	}
    }

    $g_imprime=read_glade('choix_pages_impression',
			  qw/arbre_choix_copies bloc_imprimante imprimante imp_c_agrafe bloc_fichier/);

    if($o{'methode_impression'} eq 'CUPS') {
	$w{'bloc_imprimante'}->show();

	$cups=Net::CUPS->new();

	# les imprimantes :

	my @printers = $cups->getDestinations();
	debug "Printers : ".join(' ',map { $_->getName() } @printers);
	my $p_model=cb_model(map { ($_->getName(),$_->getDescription() || $_->getName()) } @printers);
	$w{'imprimante'}->set_model($p_model);
	if(! $o{'imprimante'}) {
	    my $defaut=$cups->getDestination();
	    if($defaut) {
		$o{'imprimante'}=$defaut->getName();
	    } else {
		$o{'imprimante'}=$printers[0]->getName();
	    }
	}
	my $i=model_id_to_iter($p_model,COMBO_ID,$o{'imprimante'});
	if($i) {
	    $w{'imprimante'}->set_active_iter($i);
	}

	# transmission

	transmet_pref($g_imprime,'imp',$o{'options_impression'});
    }

    if($o{'methode_impression'} eq 'file') {
	$w{'bloc_imprimante'}->hide();
	$w{'bloc_fichier'}->show();

	transmet_pref($g_imprime,'impf',$o{'options_impression'});
    }

    $copies_store->clear();
    $projet{'_layout'}->begin_read_transaction('PRNT');
    for my $c ($projet{'_layout'}->students()) {
	$copies_store->set($copies_store->append(),COPIE_N,$c);
    }
    $projet{'_layout'}->end_transaction('PRNT');

    $w{'arbre_choix_copies'}->set_model($copies_store);

    my $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of the column containing the paper's numbers (1,2,3,...) in the table showing all available papers, from which the user will choose those he wants to print.
    my $column = Gtk2::TreeViewColumn->new_with_attributes (__"papers",
							    $renderer,
							    text=> COPIE_N );
    $w{'arbre_choix_copies'}->append_column ($column);

    $w{'arbre_choix_copies'}->get_selection->set_mode("multiple");

}

sub sujet_impressions_cancel {

    if(get_debug()) {
	reprend_pref('imp',$o{'options_impression'});
	debug(Dumper($o{'options_impression'}));
    }

    $w{'choix_pages_impression'}->destroy;
}

sub sujet_impressions_ok {
    my $os='none';
    my @e=();

    for my $i ($w{'arbre_choix_copies'}->get_selection()->get_selected_rows() ) {
	push @e,$copies_store->get($copies_store->get_iter($i),COPIE_N);
    }

    if($o{'methode_impression'} eq 'CUPS') {
	my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
	if($i ne $o{'imprimante'}) {
	    $o{'imprimante'}=$i;
	    $o{'_modifie'}=1;
	}

	reprend_pref('imp',$o{'options_impression'});

	if($o{'options_impression'}->{'_modifie'}) {
	    $o{'_modifie'}=1;
	    delete $o{'options_impression'}->{'_modifie'};
	}

	$os=join(',',map { $_."=".$o{'options_impression'}->{$_} }
		 grep { $o{'options_impression'}->{$_} }
		 (keys %{$o{'options_impression'}}) );

	debug("Printing options : $os");
    }

    if($o{'methode_impression'} eq 'file') {
	reprend_pref('impf',$o{'options_impression'});

	if($o{'options_impression'}->{'_modifie'}) {
	    $o{'_modifie'}=1;
	    delete $o{'options_impression'}->{'_modifie'};
	}

	if(!$o{'options_impression'}->{'repertoire'}) {
	    debug "Print to file : no destionation...";
	    $o{'options_impression'}->{'repertoire'}='';
	} else {
	    mkdir($o{'options_impression'}->{'repertoire'})
		if(! -e $o{'options_impression'}->{'repertoire'});
	}
    }

    $w{'choix_pages_impression'}->destroy;

    debug "Printing: ".join(",",@e);

    if(!@e) {
	# No page selected:
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  __("You did not select any sheet to print..."));
	$dialog->run;
	$dialog->destroy;
	return();
    }

    if(1+$#e <= 10) {
      # Less than 10 pages selected: is it a mistake?

      $projet{'_layout'}->begin_read_transaction('pPFP');
      my $max_p=$projet{'_layout'}->max_enter();
      my $students=$projet{'_layout'}->students_count();
      $projet{'_layout'}->end_transaction('pPFP');

      if($max_p>1) {
	# Some sheets have more than one enter-page: multiple scans
	# are not supported...
	my $resp=dialogue_apprentissage('PRINT_FEW_PAGES',
					'warning','yes-no',$students<=10,
					__("You selected only a few sheets to print.")."\n".
					__("As students are requested to write on more than one page, you must create as many exam sheets as necessary for all your students, with different sheets numbers, and print them all.")." ".
					__("If you print one or several sheets and photocopy them to have enough for all the students, <b>you won't be able to continue with AMC!</b>")."\n".
					__("Do you want to print the selected sheets anyway?"),
				       );
	return() if($resp eq 'no');
      } elsif($students<=10) {
	if($projet{'options'}->{'auto_capture_mode'} != 1) {
	  # This looks strange: a few sheets printed, a few sheets
	  # generated, and photocopy mode not selected yet. Ask the
	  # user if he wants to select this mode now.
	  my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'question','yes-no',
			      __("You selected only a few sheets to print.")."\n".
			      "<b>".__("Are you going to photocopy some printed subjects before giving them to the students?")."</b>\n".
			      __("If so, the corresponding option will be set for this project.")." ".
			      __("However, you will be able to change this when giving your first scans to AMC.")
			     );
	  my $reponse=$dialog->run;
	  $dialog->destroy;
	  my $mult=($reponse eq 'yes' ? 1 : 0);
	  if($mult != $projet{'options'}->{'auto_capture_mode'}) {
	    $projet{'options'}->{'auto_capture_mode'}=$mult;
	    $projet{'options'}->{'_modifie_ok'}=1;
	  }
	}
      }
    }

    my $fh=File::Temp->new(TEMPLATE => "nums-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@e)."\n";
    $fh->seek( 0, SEEK_END );

    commande('commande'=>["auto-multiple-choice","imprime",
			  "--methode",$o{'methode_impression'},
			  "--imprimante",$o{'imprimante'},
			  "--options",$os,
			  "--output",$o{'options_impression'}->{'repertoire'}."/copie-%e.pdf",
			  "--print-command",$o{'print_command_pdf'},
			  "--sujet",absolu($projet{'options'}->{'docs'}->[0]),
			  "--data",absolu($projet{'options'}->{'data'}),
			  "--progression-id",'impression',
			  "--progression",1,
			  "--debug",debug_file(),
			  "--fich-numeros",$fh->filename,
			  ],
	     'signal'=>2,
	     'texte'=>__"Print papers one by one...",
	     'progres.id'=>'impression',
	     'o'=>{'fh'=>$fh,'etu'=>\@e,'printer'=>$o{'imprimante'},'method'=>$o{'methode_impression'}},
	     'fin'=>sub {
		 my $c=shift;
		 close($c->{'o'}->{'fh'});
		 save_state_after_printing($c->{'o'});
	     },

	     );
}

sub save_state_after_printing {
    my $c=shift;
    my $st=AMC::State::new('directory'=>absolu('%PROJET/'));

    $st->read();

    my @files=(@{$projet{'options'}->{'docs'}},
	       absolu($projet{'options'}->{'texsrc'}));

    push @files,absolu($projet{'options'}->{'filtered_source'})
      if(-f absolu($projet{'options'}->{'filtered_source'}));

    if(!$st->check_local_md5(@files)) {
	$st=AMC::State::new('directory'=>absolu('%PROJET/'));
	$st->add_local_files(@files);
    }

    $st->add_print('printer'=>$c->{'printer'},
		   'method'=>$c->{'method'},
		   'content'=>join(',',@{$c->{'etu'}}));
    $st->write();

}

sub calcule_mep {
    if($projet{'options'}->{'docs'}->[2] !~ /\.xy$/) {
	# OLD STYLE WORKING DOCUMENTS... Not supported anymore: update!
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error', # message type
			      'ok', # which set of buttons?
			      __("Working documents are in an old format, which is not supported anymore.")." <b>"
			      .__("Please generate again the working documents!")."</b>");
	$dialog->run;
	$dialog->destroy;

	return;
    }

    commande('commande'=>["auto-multiple-choice","meptex",
			  "--debug",debug_file(),
			  "--src",absolu($projet{'options'}->{'docs'}->[2]),
			  "--progression-id",'MEP',
			  "--progression",1,
			  "--data",absolu($projet{'options'}->{'data'}),
			  ],
	     'texte'=>__"Detecting layouts...",
	     'progres.id'=>'MEP',
	     'fin'=>sub {
		 detecte_mep();
		 $projet{'_layout'}->begin_read_transaction('PGCN');
		 my $c=$projet{'_layout'}->pages_count();
		 $projet{'_layout'}->end_transaction('PGCN');
		 if($c<1) {
		     # avertissement...
		     my $dialog = Gtk2::MessageDialog
			 ->new_with_markup($w{'main_window'},
					   'destroy-with-parent',
					   'error', # message type
					   'ok', # which set of buttons?
					   __("No layout detected.")." "
					   .__("<b>Don't go through the examination</b> before fixing this problem, otherwise you won't be able to use AMC for correction."));
		     $dialog->run;
		     $dialog->destroy;

		 } else {
		     dialogue_apprentissage('MAJ_MEP_OK','','',0,
					    __("Layouts are detected.")." "
					    .sprintf(__"You can check all is correct clicking on button <i>%s</i> and looking at question pages to see if red boxes are well positioned.",__"Check layouts")." "
					    .__"Then you can proceed to printing and to examination.");
		 }
	     });
}

sub verif_mep {
    saisie_manuelle(0,0,1);
}

### Actions des boutons de la partie SAISIE

sub saisie_manuelle {
    my ($self,$event,$regarder)=@_;
    $projet{'_layout'}->begin_read_transaction('PGCN');
    my $c=$projet{'_layout'}->pages_count();
    $projet{'_layout'}->end_transaction('PGCN');
    if($c>0) {

      if(!$regarder) {
	# if auto_capture_mode is not set, ask the user...
	my $n=check_auto_capture_mode();
	if($projet{'options'}->{'auto_capture_mode'}<0) {
	  my $gsa=read_glade('choose-mode',
			     qw/saisie_auto_c_auto_capture_mode
				button_capture_go/);

	  transmet_pref($gsa,'saisie_auto',$projet{'options'});
	  my $ret=$w{'choose-mode'}->run();
	  if($ret==1) {
	    reprend_pref('saisie_auto',$projet{'options'});
	    $w{'choose-mode'}->destroy;
	  } else {
	    $w{'choose-mode'}->destroy;
	    return();
	  }
	}
      }

      # go for capture

      my $gm=AMC::Gui::Manuel::new
	(
	 'multiple'=>$projet{'options'}->{'auto_capture_mode'},
	 'data-dir'=>absolu($projet{'options'}->{'data'}),
	 'sujet'=>absolu($projet{'options'}->{'docs'}->[0]),
	 'etud'=>'',
	 'dpi'=>$o{'saisie_dpi'},
	 'seuil'=>$projet{'options'}->{'seuil'},
	 'seuil_sens'=>$o{'seuil_sens'},
	 'seuil_eqm'=>$o{'seuil_eqm'},
	 'global'=>0,
	 'encodage_interne'=>$o{'encodage_interne'},
	 'image_type'=>$o{'manuel_image_type'},
	 'retient_m'=>1,
	 'editable'=>($regarder ? 0 : 1),
	 'en_quittant'=>($regarder ? '' : \&detecte_analyse),
	);
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      __("No layout for this project.")." "
# TRANSLATORS: Here, the first %s will be replaced with "Layout detection" (a button title), and the second %s with "Preparation" (the tab title where one can find this button).
			      .sprintf(__("Please use button <i>%s</i> in <i>%s</i> before manual data capture."),
				       __"Layout detection",
				       __"Preparation"));
	$dialog->run;
	$dialog->destroy;
    }
}

sub check_auto_capture_mode {
  $projet{'_capture'}->begin_read_transaction('ckac');
  my $n=$projet{'_capture'}->n_copies;
  if($n>0 && $projet{'options'}->{'auto_capture_mode'} <0) {
    # the auto_capture_mode (sheets photocopied or not) is not set,
    # but some capture has already been done. This looks weird, but
    # it can be the case if captures were made with an old AMC
    # version, or if project parameters have not been saved...
    # So we try to detect the correct value from the capture data.
    $projet{'options'}->{'auto_capture_mode'}=
      ($projet{'_capture'}->n_photocopy() > 0 ? 1 : 0);
  }
  $projet{'_capture'}->end_transaction('ckac');
  return($n);
}

sub saisie_automatique {
    # mode can't be changed if data capture has been made already
    my $n=check_auto_capture_mode;
    $projet{'_capture'}->begin_read_transaction('adcM');
    my $mcopy=$projet{'_capture'}->max_copy_number()+1;
    $w{'saisie_auto_allocate_start'}=$mcopy;
    $projet{'_capture'}->end_transaction('adcM');

    my $gsa=read_glade('saisie_auto',
		       qw/copie_scans
			  saisie_auto_c_auto_capture_mode
			  saisie_auto_cb_allocate_ids
			  button_capture_go/);
    $w{'copie_scans'}->set_active(1);
    transmet_pref($gsa,'saisie_auto',$projet{'options'});
    $w{'saisie_auto_cb_allocate_ids'}->set_label(sprintf(__"Pre-allocate sheet ids from the page numbers, starting at %d",$mcopy));

    $w{'saisie_auto_c_auto_capture_mode'}->set_sensitive($n==0);
}

sub saisie_auto_mode_update {
  my %o=('auto_capture_mode'=>undef);
  # the mode value (auto_capture_mode) has been updated.
  valide_options_for_domain('saisie_auto',\%o,@_);
  $o{'auto_capture_mode'}=-1 if(!defined($o{'auto_capture_mode'}));
  $w{'button_capture_go'}->set_sensitive($o{'auto_capture_mode'}>=0);
  if($o{'auto_capture_mode'}==1) {
    $w{'saisie_auto_cb_allocate_ids'}->show();
  } else {
    $w{'saisie_auto_cb_allocate_ids'}->hide();
  }
}

sub saisie_auto_annule {
    $w{'saisie_auto'}->destroy();
}

sub saisie_auto_info {
  my $dialog=Gtk2::MessageDialog
    ->new_with_markup($w{'saisie_auto'},'destroy-with-parent','info','ok',
		      __("Automatic data capture can be done in two different modes:")."\n"
		      ."<b>".
# TRANSLATORS: This is a title for the AMC mode where the distributed exam papers are all different (different paper numbers at the top) -- photocopy is not used.
		      __("Different answer sheets").
		      ".</b> ".
		      __("In the most robust one, you give a different sheet (with a different sheet number) to every student. You must not photocopy subjects before distributing them.")."\n"
		      ."<b>".
# TRANSLATORS: This is a title for the AMC mode where some answer sheets have been photocopied before being distributed to the students.
		      __("Some answer sheets were photocopied").
		      ".</b> ".
		      __("In the second one (which can be used only if answer sheets to be scanned has one page) you can photocopy answer sheets and give the same subject to different students.")."\n"
		      .__("After the first automatic capture, you can't switch to the other mode.")
		      );
  $dialog->run;
  $dialog->destroy;
}

sub analyse_call {
    my (%oo)=@_;
    # make temporary file with the list of images to analyse

    my $fh=File::Temp->new(TEMPLATE => "liste-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@{$oo{'f'}})."\n";
    $fh->seek( 0, SEEK_END );

    my @args=("--debug",debug_file(),
	      ($projet{'options'}->{'auto_capture_mode'} ? "--multiple" : "--no-multiple"),
	      "--tol-marque",$o{'tolerance_marque_inf'}.','.$o{'tolerance_marque_sup'},
	      "--prop",$o{'box_size_proportion'},
	      "--bw-threshold",$o{'bw_threshold'},
	      "--progression-id",'analyse',
	      "--progression",1,
	      "--n-procs",$o{'n_procs'},
	      "--data",absolu($projet{'options'}->{'data'}),
	      "--projet",absolu('%PROJET/'),
	      "--cr",absolu($projet{'options'}->{'cr'}),
	      "--liste-fichiers",$fh->filename,
	      ($o{'ignore_red'} ? "--ignore-red" : "--no-ignore-red"),
	);

    push @args,"--pre-allocate",$oo{'allocate'} if($oo{'allocate'});

    # Diagnostic image file ?

    if($oo{'diagnostic'}) {
	push @args,"--debug-image-dir",absolu('%PROJET/cr/diagnostic');
    }

    # call AMC-analyse

    commande('commande'=>["auto-multiple-choice","analyse",
	     @args],
	     'signal'=>2,
	     'texte'=>$oo{'text'},
	     'progres.id'=>$oo{'progres'},
	     'o'=>{'fh'=>$fh},
	     'fin'=>$oo{'fin'},
	     );
}

sub saisie_auto_ok {
    my @f=sort { $a cmp $b } ($w{'saisie_auto'}->get_filenames());
    my $copie=$w{'copie_scans'}->get_active();

    reprend_pref('saisie_auto',$projet{'options'});
    $w{'saisie_auto'}->destroy();
    Gtk2->main_iteration while ( Gtk2->events_pending );

    # Begin scans pre-processing before sending them for analysis

    my @fs=();

    my $splitinfo=$w{'avancement'}->get_text();
    $w{'onglets_projet'}->set_sensitive(0);
    $w{'commande'}->show();
    $w{'annulation'}->set_sensitive(0);
    Gtk2->main_iteration while ( Gtk2->events_pending );

    # first pass: split multi-page PDF with pdftk, which uses less
    # memory than ImageMagick
    if(commande_accessible('pdftk')) {
	for my $file (@f) {
	    if($file =~ /\.pdf$/i) {

	    $w{'avancement'}->set_text(sprintf(
					   __("Splitting multi-page PDF file %s..."),
					   $file));
	    $w{'avancement'}->set_fraction(0);

	    Gtk2->main_iteration while ( Gtk2->events_pending );
		my $temp_loc=tmpdir();
		my $temp_dir = tempdir( DIR=>$temp_loc,
					CLEANUP => (!get_debug()) );

		debug "PDF split tmp dir: $temp_dir";

		system("pdftk",$file,"burst","output",
		       $temp_dir.'/page-%04d.pdf');

		opendir(my $dh, $temp_dir)
		    || debug "can't opendir $temp_dir: $!";
		push @fs, map { "$temp_dir/$_" }
		sort { $a cmp $b } grep { /^page/ } readdir($dh);
		closedir $dh;

	    } else {
		push @fs,$file;
	    }
	}
	@f=@fs;
    }

    # second pass: split other multi-page images (such as TIFF) with
    # ImageMagick, and convert vector to bitmap
    @fs=();
    for my $fich (@f) {
	my (undef,undef,$fich_n)=splitpath($fich);
	my $suffix_change='';
	my @pre_options=();

	# number of pages :
	my $np=0;
	# any scene with number > 0 ? This should cause problems with OpenCV
	my $scene=0;
	open(NP,"-|",magick_module("identify"),"-format","%s\n",$fich);
	while(<NP>) {
	    chomp();
	    if(/[^\s]/) {
		$np++;
		$scene=1 if($_ > 0);
	    }
	}
	close(NP);
	# Is this a vector format file? If so, we have to convert it
	# to bitmap
	my $vector='';
	if($fich_n =~ /\.(pdf|eps|ps)$/i) {
	    $vector=1;
	    $suffix_change='.png';
	    @pre_options=('-density',$o{'vector_scan_density'})
		if($o{'vector_scan_density'});
	}

	debug "> Scan $fich: $np page(s)".($scene ? " [has scene>0]" : "");
	if($np>1 || $scene || $vector) {
	    # split multipage image into 1-page images, and/or convert
	    # to bitmap format

	    $w{'commande'}->show();
	    $w{'avancement'}->set_text(sprintf(
					   ($vector
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be converted.
					    ? __("Converting %s to bitmap...")
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be splitted to several images (one per page).
					    : __("Splitting multi-page image %s...")),
					   $fich_n));
	    $w{'avancement'}->set_fraction(0);
	    Gtk2->main_iteration while ( Gtk2->events_pending );

	    my $temp_loc=tmpdir();
	    my $temp_dir = tempdir( DIR=>$temp_loc,
				    CLEANUP => (!get_debug()) );

	    debug "Image split tmp dir: $temp_dir";

	    my ($fxa,$fxb,$fb) = splitpath($fich);
	    if(! ($fb =~ s/\.([^.]+)$/_%04d.$1/)) {
		$fb .= '_%04d';
	    }
	    $fb.=$suffix_change;

	    system(magick_module("convert"),@pre_options,$fich,"+adjoin","$temp_dir/$fb");
	    opendir(my $dh, $temp_dir) || debug "can't opendir $temp_dir: $!";
	    my @split = grep { -f "$temp_dir/$_" } 
	      sort { $a cmp $b } readdir($dh);
	    closedir $dh;

	    # if not to be copied in project dir, put them in the
	    # same directory as original image

	    if($copie) {
		push @fs,map { "$temp_dir/$_" } @split;
	    } else {
		for(@split) {
		    my $dest=catpath($fxa,$fxb,$_);
		    debug "Moving one page to $dest";
		    move("$temp_dir/$_",$dest);
		    push @fs,$dest;
		}
	    }
	} else {
	    push @fs,$fich;
	}
    }

    @f=@fs;

    # if requested, copy files to project directory

    $w{'avancement'}->set_text(__"Copying scans to project directory...");
    Gtk2->main_iteration while ( Gtk2->events_pending );

    if($copie) {
	my @fl=();
	my $c=0;
	for my $fich (@f) {
	    my ($fxa,$fxb,$fb) = splitpath($fich);

	    # no accentuated or special characters in filename, please!
	    # this could break the process somewere...
	    $fb=NFKD($fb);
	    $fb =~ s/\pM//og;
	    $fb =~ s/[^a-zA-Z0-9.-_+]+/_/g;
	    $fb =~ s/^[^a-zA-Z0-9]/scan_/;

	    my $dest=absolu("scans/".$fb);
	    my $deplace=0;

	    if($fich ne $dest) {
	      if(-e $dest) {
		# dest file already exists: change name
		debug "File $dest already exists";
		$dest=new_filename($dest);
		debug "--> $dest";
	      }
	      if(copy($fich,$dest)) {
		push @fl,$dest;
		$deplace=1;
	      } else {
		debug "$fich --> $dest";
		debug "Copy error: $!";
	      }
	    }
	    $c+=$deplace;
	    push @fl,$fich if(!$deplace);
	}
	debug "Copying scan files: ".$c."/".(1+$#f);
	@f=@fl;
    }

    clear_old('diagnostic',
	      absolu('%PROJET/cr/diagnostic'));

    $w{'avancement'}->set_text($splitinfo);
    $w{'annulation'}->set_sensitive(1);

    analyse_call('f'=>\@f,
		 'text'=>__("Automatic data capture..."),
		 'progres'=>'analyse',
		 'allocate'=>($projet{'options'}->{'allocate_ids'} ?
			      $w{'saisie_auto_allocate_start'} : 0),
		 'fin'=>sub {
		     my $c=shift;
		     close($c->{'o'}->{'fh'});
		     detecte_analyse('apprend'=>1);
		 },
	);

}

sub choisit_liste {
    my $dial=read_glade('liste_dialog')
	->get_object('liste_dialog');

    my @f;
    if($projet{'options'}->{'listeetudiants'}) {
	@f=splitpath(absolu($projet{'options'}->{'listeetudiants'}));
    } else {
	@f=splitpath(absolu('%PROJET/'));
    }
    $f[2]='';

    $dial->set_current_folder(catpath(@f));

    my $ret=$dial->run();
    debug("Names list file choice [$ret]");

    my $file=$dial->get_filename();
    $dial->destroy();

    if($ret eq '1') {
	# file chosen
	debug("List: ".$file);
	valide_liste('set'=>$file);
    } elsif($ret eq '2') {
	# No list
	valide_liste('set'=>'');
    } else {
	# Cancel
    }
}

sub edite_liste {
    my $f=absolu($projet{'options'}->{'listeetudiants'});
    debug "Editing $f...";
    commande_parallele($o{'txt_editor'},$f);
}

sub valide_liste {
    my %oo=@_;
    debug "* valide_liste";

    if(defined($oo{'set'}) && !$oo{'nomodif'}) {
	$projet{'options'}->{'listeetudiants'}=relatif($oo{'set'});
	$projet{'options'}->{'_modifie'}=1;
    }

    my $fl=absolu($projet{'options'}->{'listeetudiants'});
    $fl='' if(!$projet{'options'}->{'listeetudiants'});

    my $fn=$fl;
    $fn =~ s/.*\///;

    if($fl) {
	$w{'liste_filename'}->set_markup("<b>$fn</b>");
	for(qw/liste_path liste_edit/) {
	    $w{$_}->set_sensitive(1);
	}
    } else {
# TRANSLATORS: Names list file : (none)
	$w{'liste_filename'}->set_markup(__"(none)");
	for(qw/liste_path liste_edit/) {
	    $w{$_}->set_sensitive(0);
	}
    }

    my $l=AMC::NamesFile::new($fl,
			      'encodage'=>bon_encodage('liste'),
			      'identifiant'=>csv_build_name(),
			      );
    my ($err,$errlig)=$l->errors();

    if($err) {
	if(!$oo{'noinfo'}) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'error','ok',
				  sprintf(__"Unsuitable names file: %d errors, first on line %d.",$err,$errlig));
	    $dialog->run;
	    $dialog->destroy;
	}
	$cb_stores{'liste_key'}=$cb_model_vide_key;
    } else {
	# problems with ID (name/surname)
	my $e=$l->problem('ID.empty');
	if($e>0) {
	    debug "NamesFile: $e empty IDs";
	    $w{'liste_refresh'}->show();
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'warning','ok',
# TRANSLATORS: Here, do not translate 'name' and 'surname' (except in french), as the column names in the students list file has to be named in english in order to be properly detected.
				  sprintf(__"Found %d empty names in names file <i>%s</i>. Check that <b>name</b> or <b>surname</b> column is present, and always filled.",$e,$fl)." ".
				  __"Edit the names file to correct it, and re-read.");
	    $dialog->run;
	    $dialog->destroy;
	} else {
	    my $d=$l->problem('ID.dup');
	    if(@$d) {
		debug "NamesFile: duplicate IDs [".join(',',@$d)."]";
		if($#{$d}>8) {
		    @$d=(@{$d}[0..8],'(and more)');
		}
		$w{'liste_refresh'}->show();
		my $dialog = Gtk2::MessageDialog
		    ->new_with_markup($w{'main_window'},
				      'destroy-with-parent',
				      'warning','ok',
				      sprintf(__"Found duplicate names: <i>%s</i>. Check that all names are different.",join(', ',@$d))." ".__"Edit the names file to correct it, and re-read.");
		$dialog->run;
		$dialog->destroy;
	    } else {
		# OK, no need to refresh
		$w{'liste_refresh'}->hide();
	    }
	}
	# transmission liste des en-tetes
	my @keys=$l->keys;
	debug "primary keys: ".join(",",@keys);
# TRANSLATORS: you can omit the [...] part, just here to explain context
	$cb_stores{'liste_key'}=cb_model('',__p("(none) [No primary key found in association list]"),
					 map { ($_,$_) }
					 (@keys));
    }
    transmet_pref($gui,'pref_assoc',$projet{'options'},{},{'liste_key'=>1});
    assoc_state();
}

### Actions des boutons de la partie NOTATION

sub check_possible_assoc {
    my ($code)=@_;
    if(! -s absolu($projet{'options'}->{'listeetudiants'})) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
# TRANSLATORS: Here, %s will be replaced with the name of the tab "Data capture".
			      sprintf(__"Before associating names to papers, you must choose a students list file in tab \"%s\".",
				      __"Data capture"));
	$dialog->run;
	$dialog->destroy;
    } elsif(!$projet{'options'}->{'liste_key'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      __("Please choose a key from primary keys in students list before association."));
	$dialog->run;
	$dialog->destroy;
    } elsif($code && ! $projet{'options'}->{'assoc_code'}) {
	my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'error','ok',
			      __("Please choose a code (made with LaTeX command \\AMCcode) before automatic association."));
	$dialog->run;
	$dialog->destroy;
    } else {
	return(1);
    }
    return(0);
}

# manual association
sub associe {
    return() if(!check_possible_assoc(0));
    if(-f absolu($projet{'options'}->{'listeetudiants'})) {
      my $ga=AMC::Gui::Association::new('cr'=>absolu($projet{'options'}->{'cr'}),
					'data_dir'=>absolu($projet{'options'}->{'data'}),
					'liste'=>absolu($projet{'options'}->{'listeetudiants'}),
					'liste_key'=>$projet{'options'}->{'liste_key'},
					'identifiant'=>csv_build_name(),

					'fichier-liens'=>absolu($projet{'options'}->{'association'}),
					'global'=>0,
					'assoc-ncols'=>$o{'assoc_ncols'},
					'encodage_liste'=>bon_encodage('liste'),
					'encodage_interne'=>$o{'encodage_interne'},
					'rtl'=>$projet{'options'}->{'annote_rtl'},
					'fin'=>sub {
					  assoc_state();
					},
					'size_prefs'=>($o{'conserve_taille'} ? \%o : ''),
				       );
      if($ga->{'erreur'}) {
	my $dialog = Gtk2::MessageDialog
	  ->new($w{'main_window'},
		'destroy-with-parent',
		'error','ok',
		$ga->{'erreur'});
	$dialog->run;
	$dialog->destroy;
      }
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
# TRANSLATORS: Here, %s will be replaced with "Students identification", which refers to a paragraph in the tab "Marking" from AMC main window.
		  sprintf(__"Before associating names to papers, you must choose a students list file in paragraph \"%s\".",
			  __"Students identification"));
	$dialog->run;
	$dialog->destroy;

    }
}

# automatic association
sub associe_auto {
    return() if(!check_possible_assoc(1));

    commande('commande'=>["auto-multiple-choice","association-auto",
			  pack_args("--data",absolu($projet{'options'}->{'data'}),
				    "--notes-id",$projet{'options'}->{'assoc_code'},
				    "--liste",absolu($projet{'options'}->{'listeetudiants'}),
				    "--liste-key",$projet{'options'}->{'liste_key'},
				    "--csv-build-name",csv_build_name(),
				    "--encodage-liste",bon_encodage('liste'),
				    "--debug",debug_file(),
				   ),
	     ],
	     'texte'=>__"Automatic association...",
	     'fin'=>sub {
		 assoc_state();
		 assoc_resultat();
	     },
	);
}

# automatic association finished : explain what to do after
sub assoc_resultat {
    my $mesg=1;

    $projet{'_association'}->begin_read_transaction('ARCC');
    my ($auto,$man,$both)=$projet{'_association'}->counts();
    $projet{'_association'}->end_transaction('ARCC');

    my $dialog=Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'info','ok',
			sprintf(__("Automatic association completed: %d students recognized."),$auto).
# TRANSLATORS: Here %s and %s will be replaced with two parameters names: "Primary key from this list" and "Code name for automatic association".
			($auto==0 ? "\n<b>".sprintf(__("Please check \"%s\" and \"%s\" values and try again."),
						    __("Primary key from this list"),
						    __("Code name for automatic association"))."</b>" : "")
		       );
    $dialog->run;
    $dialog->destroy;

    dialogue_apprentissage('ASSOC_AUTO_OK','','',0,
			   __("Automatic association is now finished. You can ask for manual association to check that all is fine and, if necessary, read manually students names which have not been automatically identified.")) if($auto>0);
}

sub valide_cb {
    my ($var,$cb)=@_;
    my $cbc=$cb->get_active();
    if($cbc xor $$var) {
	$$var=$cbc;
	$projet{'options'}->{'_modifie'}=1;
	debug "* valide_cb";
    }
}

sub valide_options_correction {
    my ($ww,$o)=@_;
    my $name=$ww->get_name();
    debug "Options validation from $name";
    if(!$w{$name}) {
	debug "WARNING: Option validation failed, unknown name $name.";
    } else {
	valide_cb(\$projet{'options'}->{$name},$w{$name});
    }
}

sub valide_options_for_domain {
    my ($domain,$oo,$widget,$user_data)=@_;
    $oo=$projet{'options'} if(!$oo);
    if($widget) {
	my $name=$widget->get_name();
	debug "<$domain> options validation for widget $name";

	if($name =~ /${domain}_[a-z]+_(.*)/) {
	    reprend_pref($domain,$oo,'',{$1=>1});
	} else {
	  debug "Widget $name is not in domain <$domain>!";
	}
    } else {
	debug "<$domain> options validation: ALL";
	reprend_pref($domain,$oo);
    }
}

sub valide_options_association {
    valide_options_for_domain('pref_assoc','',@_);
}

sub valide_options_preparation {
    valide_options_for_domain('pref_prep','',@_);
}

sub filter_changed {
  my (@args)=@_;

  # check it is a different value...

  debug "Filter changed callback / options=".$projet{'options'}->{'filter'};

  my %oo=('filter'=>$projet{'options'}->{'filter'});
  valide_options_for_domain('pref_prep',\%oo,@_);
  return if(!$oo{'_modifie'});

  debug "Filter changed -> ".$oo{'filter'};

  # working document already built: ask for confirmation

  if(-f absolu($projet{'options'}->{'docs'}->[0])) {
    debug "Ask for confirmation";
    my $text;
    if($projet{'_capture'}->n_pages_transaction()>0) {
      $text=__("The working documents are already prepared with the current file format. If you change the file format, working documents and all other data for this project will be ereased.").' '
	.__("Do you wish to continue?")." "
	  .__("Click on Ok to erease old working documents and change file format, and on Cancel to get back to the same file format.")
	    ."\n<b>".__("To allow the use of an already printed question, cancel!")."</b>";
    } else {
      $text=__("The working documents are already prepared with the current file format. If you change the file format, working documents will be ereased.").' '
	.__("Do you wish to continue?")." "
	  .__("Click on Ok to erease old working documents and change file format, and on Cancel to get back to the same file format.");
    }
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'question','ok-cancel',$text);
    my $reponse=$dialog->run;
    $dialog->destroy;

    if($reponse eq 'cancel') {
      transmet_pref($gui,'pref_prep',$projet{'options'});
      return(0);
    }

    clear_processing('doc:');

  }

  valide_options_preparation(@args);

  # No source created: change source filename

  if(!-f absolu($projet{'options'}->{'texsrc'})) {
    $projet{'options'}->{'texsrc'}='%PROJET/'.
      ("AMC::Filter::register::".$projet{'options'}->{'filter'})
	->default_filename();
    $w{'state_src'}->set_text(absolu($projet{'options'}->{'texsrc'}));
  }

}

sub valide_options_notation {
    valide_options_for_domain('notation','',@_);
    if($projet{'options'}->{'_modifie'} =~ /\bregroupement_compose\b/) {
      $projet{'_report'}->begin_transaction('RCch');
      $projet{'_report'}->variable('grouped_uptodate',-3);
      $projet{'_report'}->end_transaction('RCch');
    }
    $w{'groupe_model'}->set_sensitive($projet{'options'}->{'regroupement_type'} eq 'STUDENTS');
}

sub change_liste_key {
  debug "New liste_key: ".$projet{'options'}->{'liste_key'};
  if ($projet{'options'}->{'liste_key'}) {

    $projet{'_association'}->begin_read_transaction('cLky');
    my $assoc_liste_key=$projet{'_association'}->variable('key_in_list');
    $assoc_liste_key='' if(!$assoc_liste_key);
    my ($auto,$man,$both)=$projet{'_association'}->counts();
    $projet{'_association'}->end_transaction('cLky');

    debug "Association [$assoc_liste_key] counts: AUTO=$auto MANUAL=$man BOTH=$both";

    if ($assoc_liste_key ne $projet{'options'}->{'liste_key'}
	&& $auto+$man>0) {
      # liste_key has changed and some association has been
      # made with another liste_key

      if ($man>0) {
	# manual association work has been made

	my $dialog=Gtk2::MessageDialog
	  ->new_with_markup($w{'main_window'},
			    'destroy-with-parent',
			    'warning','yes-no',
			    sprintf(__("The primary key from the students list has been set to \"%s\", which is not the value from the association data."),$projet{'options'}->{'liste_key'})." ".
			    sprintf(__("Some manual association data has be found, which will be lost if the primary key is changed. Do you want to switch back to the primary key \"%s\" and keep association data?"),$assoc_liste_key)
			   );
	my $resp=$dialog->run;
	$dialog->destroy;

	if ($resp eq 'no') {
	  # clears association data
	  clear_processing('assoc');
	  # automatic association run
	  if ($projet{'options'}->{'assoc_code'} && $auto>0) {
	    associe_auto;
	  }
	} else {
	  $projet{'options'}->{'liste_key'}=$assoc_liste_key;
	  transmet_pref($gui,'pref_assoc',$projet{'options'},{},{'liste_key'=>1});
	}
      } else {
	if ($projet{'options'}->{'assoc_code'}) {
	  # only automated association, easy to re-run
	  my $dialog=Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'info','ok',
			      sprintf(__("The primary key from the students list has been set to \"%s\", which is not the value from the association data."),$projet{'options'}->{'liste_key'})." ".
			      __("Automatic papers/students association will be re-run to update the association data.")
			     );
	  $dialog->run;
	  $dialog->destroy;

	  clear_processing('assoc');
	  associe_auto();
	}
      }
    }
  }
  assoc_state();
}

sub voir_notes {
  $projet{'_scoring'}->begin_read_transaction('smMC');
  my $c=$projet{'_scoring'}->marks_count;
  $projet{'_scoring'}->end_transaction('smMC');
  if($c>0) {
    my $n=AMC::Gui::Notes::new('scoring'=>$projet{'_scoring'});
  } else {
    my $dialog = Gtk2::MessageDialog
      ->new($w{'main_window'},
	    'destroy-with-parent',
	    'info','ok',
	    sprintf(__"Papers are not yet corrected: use button \"%s\".",
# TRANSLATORS: This is a button: "Mark" is here an action to be called by the user. When clicking this button, the user requests scores to be computed for all students.
		    __"Mark"));
    $dialog->run;
    $dialog->destroy;
  }
}

sub noter {
    if($projet{'options'}->{'maj_bareme'}) {
	my $n_copies=$projet{'options'}->{'nombre_copies'};
	$projet{'_layout'}->begin_read_transaction('STUD');
	my @mep_etus=$projet{'_layout'}->students();
	$projet{'_layout'}->end_transaction('STUD');
	my $n_mep=$mep_etus[$#mep_etus];
	if($n_copies<$n_mep) {
	    # number of requested copies is less than the number of
	    # prepared copies: check that it is sufficient (look at
	    # greater copy number within scans), and use a larger
	    # one if not.
	    debug "Requested $n_copies copies for scoring strategy, but has $n_mep layouts";
	    my @students=($projet{'_capture'}->students_transaction());
	    my $n_an=$students[$#students];
	    debug "Max used copy number: $n_an";
	    $n_copies=$n_an if($n_an>$n_copies);
	}
	commande('commande'=>["auto-multiple-choice","prepare",
			      "--n-copies",$n_copies,
			      "--with",moteur_latex(),
			      "--filter",$projet{'options'}->{'filter'},
			      "--filtered-source",absolu($projet{'options'}->{'filtered_source'}),
			      "--debug",debug_file(),
			      "--progression-id",'bareme',
			      "--progression",1,
			      "--data",absolu($projet{'options'}->{'data'}),
			      "--mode","b",
			      absolu($projet{'options'}->{'texsrc'}),
			      ],
		 'texte'=>__"Extracting marking scale...",
		 'fin'=>\&noter_postcorrect,
		 'progres.id'=>'bareme');
    } else {
	noter_calcul('','');
    }
}

my $g_pcid;
my %postcorrect_ids=();
my $postcorrect_copy_0;
my $postcorrect_copy_1;
my $postcorrect_student_min;
my $postcorrect_student_max;


sub noter_postcorrect {

    # check marking scale data: in PostCorrect mode, ask for a sheet
    # number to get right answers from...

    if($projet{'_scoring'}->variable_transaction('postcorrect_flag')) {

	debug "PostCorrect option ON";

	# gets available sheet ids

	%postcorrect_ids=();

	$projet{'_capture'}->begin_read_transaction('PCex');
	my $sth=$projet{'_capture'}->statement('studentCopies');
	$sth->execute;
	while(my $sc=$sth->fetchrow_hashref) {
	  $postcorrect_student_min=$sc->{'student'} if(!defined($postcorrect_student_min));
	  $postcorrect_ids{$sc->{'student'}}->{$sc->{'copy'}}=1;
	  $postcorrect_student_max=$sc->{'student'};
	}
	$projet{'_capture'}->end_transaction('PCex');

	# ask user for a choice

	$g_pcid=read_glade('choix_postcorrect',
			   qw/postcorrect_student postcorrect_copy
			      postcorrect_photo postcorrect_apply/);

	AMC::Gui::PageArea::add_feuille($w{'postcorrect_photo'});
	$w{'postcorrect_photo'}
	  ->signal_connect('expose_event'=>\&AMC::Gui::PageArea::expose_drawing);

	debug "Student range: $postcorrect_student_min,$postcorrect_student_max\n";
	$w{'postcorrect_student'}->set_range($postcorrect_student_min,$postcorrect_student_max);

	if($projet{'options'}->{'postcorrect_student'}) {
	  for (qw/student copy/) {
	    $w{'postcorrect_'.$_}
	      ->set_value($projet{'options'}->{'postcorrect_'.$_});
	  }
	} else {
	  $w{'postcorrect_student'}->set_value($postcorrect_student_min);
	}

    } else {
	noter_calcul('','');
    }
}

sub postcorrect_change_copy {
    my $student=$w{'postcorrect_student'}->get_value();
    my $copy=$w{'postcorrect_copy'}->get_value();

    $w{'postcorrect_apply'}->set_sensitive($postcorrect_ids{$student}->{$copy});

    $projet{'_capture'}->begin_read_transaction('PCCN');
    my ($f)=$projet{'_capture'}->zone_images($student,$copy,ZONE_NAME);
    $projet{'_capture'}->end_transaction('PCCN');
    if(!defined($f)) {
      $f='' ;
    } else {
      $f=absolu($projet{'options'}->{'cr'})."/$f";
    }
    debug "Postcorrect name field image: $f";
    if(-f $f) {
      $w{'postcorrect_photo'}->set_image($f);
    } else {
      $w{'postcorrect_photo'}->set_image('NONE');
    }
}

sub postcorrect_change {
  my $student=$w{'postcorrect_student'}->get_value();

  my @c=sort { $a <=> $b } (keys %{$postcorrect_ids{$student}});
  $postcorrect_copy_0=$c[0];
  $postcorrect_copy_1=$c[$#c];

  debug "Postcorrect copy range for student $student: $c[0],$c[$#c]\n";
  $w{'postcorrect_copy'}->set_range($c[0],$c[$#c]);

  postcorrect_change_copy;
}

sub postcorrect_previous {
    my $student=$w{'postcorrect_student'}->get_value();
    my $copy=$w{'postcorrect_copy'}->get_value();

    $copy--;
    if($copy<$postcorrect_copy_0) {
      $student--;
      if($student>=$postcorrect_student_min) {
	$w{'postcorrect_student'}->set_value($student);
	$w{'postcorrect_copy'}->set_value(10000);
      }
    } else {
      $w{'postcorrect_copy'}->set_value($copy);
    }
}

sub postcorrect_next {
    my $student=$w{'postcorrect_student'}->get_value();
    my $copy=$w{'postcorrect_copy'}->get_value();

    $copy++;
    if($copy>$postcorrect_copy_1) {
      $student++;
      if($student<=$postcorrect_student_max) {
	$w{'postcorrect_student'}->set_value($student);
	$w{'postcorrect_copy'}->set_value(0);
      }
    } else {
      $w{'postcorrect_copy'}->set_value($copy);
    }
}

sub choix_postcorrect_cancel {
    $w{'choix_postcorrect'}->destroy();
}

sub choix_postcorrect_ok {
    my $student=$w{'postcorrect_student'}->get_value();
    my $copy=$w{'postcorrect_copy'}->get_value();
    $w{'choix_postcorrect'}->destroy();

    if( $student != $projet{'options'}->{'postcorrect_student'}
      || $copy !=$projet{'options'}->{'postcorrect_copy'} ) {
	$projet{'options'}->{'postcorrect_student'}=$student;
	$projet{'options'}->{'postcorrect_copy'}=$copy;
	$projet{'options'}->{'_modifie_ok'}=1;
    }

    noter_calcul($student,$copy);
}

sub noter_calcul {

    my ($postcorrect_student,$postcorrect_copy)=@_;

    debug "Using sheet $postcorrect_student:$postcorrect_copy to get correct answers"
	if($postcorrect_student);

    # computes marks.

    commande('commande'=>["auto-multiple-choice","note",
			  "--debug",debug_file(),
			  "--data",absolu($projet{'options'}->{'data'}),
			  "--seuil",$projet{'options'}->{'seuil'},

			  "--grain",$projet{'options'}->{'note_grain'},
			  "--arrondi",$projet{'options'}->{'note_arrondi'},
			  "--notemax",$projet{'options'}->{'note_max'},
			  "--plafond",$projet{'options'}->{'note_max_plafond'},
			  "--notemin",$projet{'options'}->{'note_min'},
			  "--postcorrect-student",$postcorrect_student,
			  "--postcorrect-copy",$postcorrect_copy,

			  "--encodage-interne",$o{'encodage_interne'},
			  "--progression-id",'notation',
			  "--progression",1,
			  ],
	     'signal'=>2,
	     'texte'=>__"Computing marks...",
	     'progres.id'=>'notation',
	     'fin'=>sub {
		 noter_resultat();
	     },
	     );
}

sub noter_resultat {
  $projet{'_scoring'}->begin_read_transaction('MARK');
  my $avg=$projet{'_scoring'}->average_mark;

  if(defined($avg)) {
    state_image('marking','gtk-yes');
# TRANSLATORS: This is the marks mean for all students.
    $w{'state_marking'}->set_text(sprintf(__"Mean: %.2f",$avg));
  } else {
    state_image('marking','gtk-dialog-error');
    $w{'state_marking'}->set_text(__("No marks computed"));
  }

  my @codes=$projet{'_scoring'}->codes;
  $projet{'_scoring'}->end_transaction('MARK');

  debug "Codes : ".join(',',@codes);
# TRANSLATORS: you can omit the [...] part, just here to explain context
  $cb_stores{'assoc_code'}=cb_model(''=>__p("(none) [No code found in LaTeX file]"),
				    map { $_=>decode($o{'encodage_latex'},$_) }
				    (@codes));
  transmet_pref($gui,'pref_assoc',$projet{'options'},{},{'assoc_code'=>1});

  $w{'onglet_reports'}->set_sensitive(defined($avg));
}

sub assoc_state {
  my $i='gtk-dialog-question';
  my $t='';
  if(! -s absolu($projet{'options'}->{'listeetudiants'})) {
    $t=__"No students list file";
  } elsif(!$projet{'options'}->{'liste_key'}) {
    $t=__"No primary key from students list file";
  } else {
    $projet{'_association'}->begin_read_transaction('ARST');
    my $mc=$projet{'_association'}->missing_count;
    $projet{'_association'}->end_transaction('ARST');
    if($mc) {
      $t=sprintf((__"Missing identification for %d answer sheets"),$mc);
    } else {
      $t=__"All completed answer sheets are associated with a student name";
      $i='gtk-yes';
    }
  }
  state_image('assoc',$i);
  $w{'state_assoc'}->set_text($t);
}

sub opt_symbole {
    my ($s)=@_;
    my $k=$s;
    my $type='none';
    my $color='red';

    $k =~ s/-/_/g;
    $type=$o{'symbole_'.$k.'_type'} if(defined($o{'symbole_'.$k.'_type'}));
    $color=$o{'symbole_'.$k.'_color'} if(defined($o{'symbole_'.$k.'_color'}));

    return("$s:$type/$color");
}

sub select_students {
  my ($id_file)=@_;

  # restore last setting
  my %ids=();
  if (open(IDS,$id_file)) {
    while (<IDS>) {
      chomp;
      $ids{$_}=1 if(/^[0-9]+(:[0-9]+)?$/);
    }
    close(IDS);
  }
  # dialog to let the user choose...
  my $gstud=read_glade('choose_students',
		       qw/choose_students_area students_instructions
			  students_select_list students_list_search/);
  my $lk=$projet{'options'}->{'liste_key'};

  $col=$w{'choose_students'}->style()->bg('prelight');
  for my $s (qw/normal insensitive/) {
    for my $k (qw/students_instructions/) {
      $w{$k}->modify_base($s,$col);
    }
  }
  my $students_store=Gtk2::ListStore
    ->new('Glib::String','Glib::String','Glib::String',
	  'Glib::String','Glib::String',
	  'Glib::Boolean','Glib::Boolean');
  my $filter=Gtk2::TreeModelFilter->new($students_store);
  $filter->set_visible_column(5);
  $w{'students_list_store'}=$students_store;
  $w{'students_list_filter'}=$filter;

  $w{'students_select_list'}->set_model($filter);
  my $renderer=Gtk2::CellRendererText->new;
  my $column = Gtk2::TreeViewColumn->new_with_attributes (__"sheet ID",
							  $renderer,
							  text=> 0);
  $column->set_sort_column_id(0);
  $w{'students_select_list'}->append_column ($column);

  if($lk) {
    $column = Gtk2::TreeViewColumn->new_with_attributes ($lk,
							 $renderer,
							 text=> 4);
    $column->set_sort_column_id(4);
    $w{'students_select_list'}->append_column ($column);
  }

  $column = Gtk2::TreeViewColumn->new_with_attributes (__"student",
						       $renderer,
						       text=> 1);
  $column->set_sort_column_id(1);
  $w{'students_select_list'}->append_column ($column);

  my $fl=absolu($projet{'options'}->{'listeetudiants'});
  my $l=AMC::NamesFile::new($fl,
			    'encodage'=>bon_encodage('liste'),
			    'identifiant'=>csv_build_name(),
			   );
  $projet{'_capture'}->begin_read_transaction('gSLi');
  my $key=$projet{'_association'}->variable('key_in_list');
  my @selected_iters=();
  for my $sc ($projet{'_capture'}->student_copies) {
    my $id=$projet{'_association'}->get_real(@$sc);
    my $iter=$students_store->append;
    my ($name)=$l->data($key,$id);
    $students_store->set($iter,
			 0=>studentids_string(@$sc),
			 1=>$name->{'_ID_'},
			 2=>$sc->[0],3=>$sc->[1],
			 5=>1,
			);
    $students_store->set($iter,4=>$name->{$lk}) if($lk);
    push @selected_iters,$iter if($ids{studentids_string(@$sc)});
  }
  $projet{'_capture'}->end_transaction('gSLi');

  $w{'students_select_list'}->get_selection->set_mode(GTK_SELECTION_MULTIPLE);
  for (@selected_iters) {
    $w{'students_select_list'}->get_selection->select_iter($filter->convert_child_iter_to_iter($_));
  }

  my $resp=$w{'choose_students'}->run;

  select_students_save_selected_state();

  my @k=();

  if($resp==1) {
    $students_store->foreach(sub {
			       my ($model,$path,$iter,$user)=@_;
			       push @k,[$students_store->get($iter,2,3)]
				 if($students_store->get($iter,6));
			     });
  }

  $w{'choose_students'}->destroy;

  if ($resp==1) {
    open(IDS,">$id_file");
    for (@k) {
      print IDS studentids_string(@$_)."\n";
    }
    close(IDS);
  } else {
    return();
  }

  return(1);
}

sub select_students_save_selected_state {
  my $sel=$w{'students_select_list'}->get_selection;
  my $f=$w{'students_list_filter'};
  my $s=$w{'students_list_store'};
  $f->foreach(sub {
		my ($model,$path,$iter,$user)=@_;
		$s->set($f->convert_iter_to_child_iter($iter),
			6=>$sel->iter_is_selected($iter));
	      });
}

sub select_students_recover_selected_state {
  my $sel=$w{'students_select_list'}->get_selection;
  my $f=$w{'students_list_filter'};
  my $s=$w{'students_list_store'};
  $f->foreach(sub {
		my ($model,$path,$iter,$user)=@_;
		if($s->get($f->convert_iter_to_child_iter($iter),6)) {
		  $sel->select_iter($iter);
		} else {
		  $sel->unselect_iter($iter);
		}
	      });
}

sub select_students_search {
  select_students_save_selected_state();
  my $pattern=$w{'students_list_search'}->get_text;
  my $s=$w{'students_list_store'};
  $s->foreach(sub {
		my ($model,$path,$iter,$user)=@_;
		my ($id,$n,$nb)=$s->get($iter,0,1,4);
		$s->set($iter,5=>
			((!$pattern)
			 || $id =~ /$pattern/i || $n =~ /$pattern/i
			 || $nb =~ /$pattern/i ? 1 : 0));
		return(0);
	      });
  select_students_recover_selected_state();
}

sub select_students_all {
  $w{'students_list_search'}->set_text('');
}

sub annote_copies {
  my ($and_regroupe)=@_;
  my $id_file='';

  if($projet{'options'}->{'regroupement_copies'} eq 'SELECTED') {
    # use a file in project directory to store students ids for which
    # sheets will be annotated
    $id_file=absolu('%PROJET/selected-ids');
    return() if(!select_students($id_file));
  }

  commande('commande'=>["auto-multiple-choice","annote",
			pack_args("--debug",debug_file(),
				  "--progression-id",'annote',
				  "--progression",1,
				  "--projet",absolu('%PROJET/'),
				  "--projets",absolu('%PROJETS/'),
				  "--ch-sign",$o{'annote_chsign'},
				  "--cr",absolu($projet{'options'}->{'cr'}),
				  "--data",absolu($projet{'options'}->{'data'}),
				  "--id-file",$id_file,
				  "--taille-max",$o{'taille_max_correction'},
				  "--qualite",$o{'qualite_correction'},
				  "--line-width",$o{'symboles_trait'},

				  "--indicatives",$o{'symboles_indicatives'},
				  "--symbols",join(',',map { opt_symbole($_); } (qw/0-0 0-1 1-0 1-1/)),
				  "--position",$projet{'options'}->{'annote_position'},
				  "--pointsize-nl",$o{'annote_ps_nl'},
				  "--ecart",$o{'annote_ecart'},
				  "--verdict",$projet{'options'}->{'verdict'},
				  "--verdict-question",$projet{'options'}->{'verdict_q'},
				  "--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
				  "--noms-encodage",bon_encodage('liste'),
				  "--csv-build-name",csv_build_name(),
				  ($projet{'options'}->{'annote_rtl'} ? "--rtl" : "--no-rtl"),
				  "--changes-only",
				 )
		       ],
	   'texte'=>__"Annotating papers...",
	   'progres.id'=>'annote',
	   'fin'=>sub {
	     my $c=shift;
	     my $n=$c->variable('n_processed');
	     regroupement_go($n>0,$id_file) if($and_regroupe);
	   },
	  );
}

sub annotate_papers {

  valide_options_notation();

  annote_copies(1);
}

sub regroupement_go {
  my ($from_annotate,$id_file)=@_;

  maj_export();

  my $single_output='';

  if($projet{'options'}->{'regroupement_type'} eq 'ALL') {
    $single_output=($id_file ?
# TRANSLATORS: File name for single annotated answer sheets with only some selected students. Please use simple characters.
		    (__("Selected_students")).".pdf" :
# TRANSLATORS: File name for single annotated answer sheets with all students. Please use simple characters.
		    (__("All_students")).".pdf" );
  }

  my $type=($single_output ? REPORT_SINGLE_ANNOTATED_PDF : REPORT_ANNOTATED_PDF);

  # Looks if a rename is sufficient, or if one has to group again JPEG files:

  my $group=($from_annotate ? 'some annotated pages were rebuilt' : '');
  if(!$group) {
    $projet{'_report'}->begin_read_transaction('RgFO');
    $group='reports missing'
      if(!$single_output &&
	 ($projet{'_report'}->type_count($type)
	  != $projet{'_capture'}->n_copies() ));
    $group='no report'
      if(!$group && $single_output && $projet{'_report'}->type_count($type)<1);
    $group='reports not found'
      if(!$group && !$projet{'_report'}->all_there($type,absolu('%PROJET/')));
    $group='type changed'
      if(!$group &&
	 $projet{'_report'}->variable('last_group_type') != $type);
    $group='not up to date'
      if(!$group &&
	 $projet{'_report'}->variable('grouped_uptodate')<=0);
    $group='selected only'
      if(!$group && $id_file);
    $projet{'_report'}->end_transaction('RgFO');
  }

  debug "Group? $group\n";

  if($group) {
    # Group JPG annotated pages.
    commande('commande'=>
	     ["auto-multiple-choice","regroupe",
	      pack_args(
			"--debug",debug_file(),
			"--id-file",$id_file,
			($projet{'options'}->{'regroupement_compose'} ? "--compose" : "--no-compose"),
			"--projet",absolu('%PROJET'),
			"--sujet",absolu($projet{'options'}->{'docs'}->[0]),
			"--data",absolu($projet{'options'}->{'data'}),
			"--tex-src",absolu($projet{'options'}->{'texsrc'}),
			"--with",moteur_latex(),
			"--filter",$projet{'options'}->{'filter'},
			"--filtered-source",absolu($projet{'options'}->{'filtered_source'}),
			"--n-copies",$projet{'options'}->{'nombre_copies'},
			"--progression-id",'regroupe',
			"--progression",1,
			"--modele",$projet{'options'}->{'modele_regroupement'},
			"--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
			"--noms-encodage",bon_encodage('liste'),
			"--csv-build-name",csv_build_name(),
			"--single-output",$single_output,
			"--sort",$projet{'options'}->{'export_sort'},
			($id_file ? "--no-register" : "--register"),
			($o{'ascii_filenames'} ? "--force-ascii" : "--no-force-ascii"),
		       )
	     ],
	     'signal'=>2,
	     'clear'=>'',
	     'texte'=>__"Grouping students annotated pages together...",
	     'progres.id'=>'regroupe',
	    );
  } else {
    # Only rename correct old files
    commande('commande'=>
	     ["auto-multiple-choice","regroupe",
	      pack_args(
			"--debug",debug_file(),
			"--id-file",$id_file,
			"--rename",
			"--projet",absolu('%PROJET'),
			"--data",absolu($projet{'options'}->{'data'}),
			"--progression-id",'regroupe',
			"--progression",1,
			"--modele",$projet{'options'}->{'modele_regroupement'},
			"--fich-noms",absolu($projet{'options'}->{'listeetudiants'}),
			"--noms-encodage",bon_encodage('liste'),
			"--csv-build-name",csv_build_name(),
			"--single-output",$single_output,
			($o{'ascii_filenames'} ? "--force-ascii" : "--no-force-ascii"),
		       )
	     ],
	     'signal'=>2,
	     'clear'=>'',
	     'texte'=>__"Renaming annotated files with new model...",
	     'progres.id'=>'regroupe',
	    );
  }
}

sub view_dir {
    my ($dir)=@_;

    debug "Look at $dir";
    my $seq=0;
    my @c=map { $seq+=s/[%]d/$dir/g;$_; } split(/\s+/,$o{'dir_opener'});
    push @c,$dir if(!$seq);
    # nautilus attend des arguments dans l'encodage specifie par LANG & co.
    @c=map { encode($encodage_systeme,$_); } @c;

    commande_parallele(@c);
}

sub open_exports_dir {
    view_dir(absolu('%PROJET/exports/'));
}

sub open_templates_dir {
    view_dir($o{'rep_modeles'});
}

sub regarde_regroupements {
    view_dir(absolu($projet{'options'}->{'cr'})."/corrections/pdf");
}

sub plugins_browse {
  view_dir("$o_dir/plugins");
}

###

sub activate_apropos {
    my $gap=read_glade('apropos');
}

sub close_apropos {
    $w{'apropos'}->destroy();
}

sub activate_doc {
    my ($w,$lang)=@_;

    #print STDERR "$w / $lang\n";

    my $url='file://'.$hdocdir;
    $url.="auto-multiple-choice.$lang/index.html"
	if($lang && -f $hdocdir."auto-multiple-choice.$lang/index.html");

    my $seq=0;
    my @c=map { $seq+=s/[%]u/$url/g;$_; } split(/\s+/,$o{'html_browser'});
    push @c,$url if(!$seq);
    @c=map { encode($encodage_systeme,$_); } @c;

    commande_parallele(@c);
}

###

###

# transmet les preferences vers les widgets correspondants
# _c_ combo box (menu)
# _cb_ check button
# _ce_ combo box entry
# _col_ color chooser
# _f_ file name
# _s_ spin button
# _t_ text
# _v_ check button
# _x_ one line text

sub transmet_pref {
    my ($gap,$prefixe,$h,$alias,$seulement)=@_;

    for my $t (keys %$h) {
	if(!$seulement || $seulement->{$t}) {
	my $ta=$t;
	$ta=$alias->{$t} if($alias->{$t});

	my $wp=$gap->get_object($prefixe.'_t_'.$ta) || $w{$prefixe.'_t_'.$ta};
	if($wp) {
	    $w{$prefixe.'_t_'.$t}=$wp;
	    $wp->get_buffer->set_text($h->{$t});
	}
	$wp=$gap->get_object($prefixe.'_x_'.$ta) || $w{$prefixe.'_x_'.$ta};
	if($wp) {
	    $w{$prefixe.'_x_'.$t}=$wp;
	    $wp->set_text($h->{$t});
	}
	$wp=$gap->get_object($prefixe.'_f_'.$ta) || $w{$prefixe.'_f_'.$ta};
	if($wp) {
	    $w{$prefixe.'_f_'.$t}=$wp;
	    if($wp->get_action =~ /-folder$/i) {
		$wp->set_current_folder($h->{$t});
	    } else {
		$wp->set_filename($h->{$t});
	    }
	}
	$wp=$gap->get_object($prefixe.'_v_'.$ta) || $w{$prefixe.'_v_'.$ta};
	if($wp) {
	    $w{$prefixe.'_v_'.$t}=$wp;
	    $wp->set_active($h->{$t});
	}
	$wp=$gap->get_object($prefixe.'_s_'.$ta) || $w{$prefixe.'_s_'.$ta};
	if($wp) {
	    $w{$prefixe.'_s_'.$t}=$wp;
	    $wp->set_value($h->{$t});
	}
	$wp=$gap->get_object($prefixe.'_col_'.$ta) || $w{$prefixe.'_col_'.$ta};
	if($wp) {
	    $w{$prefixe.'_col_'.$t}=$wp;
	    $wp->set_color(Gtk2::Gdk::Color->parse($h->{$t}));
	}
	$wp=$gap->get_object($prefixe.'_cb_'.$ta) || $w{$prefixe.'_cb_'.$ta};
	if($wp) {
	    $w{$prefixe.'_cb_'.$t}=$wp;
	    $wp->set_active($h->{$t});
	}
	$wp=$gap->get_object($prefixe.'_c_'.$ta) || $w{$prefixe.'_c_'.$ta};
	if($wp) {
	    if($cb_stores{$ta}) {
	      $w{$prefixe.'_c_'.$t}=$wp;
	      debug "CB_STORE($t) ALIAS $ta modifie ($t=>$h->{$t})";
	      $wp->set_model($cb_stores{$ta});
	      my $i=model_id_to_iter($wp->get_model,COMBO_ID,$h->{$t});
	      if($i) {
		debug("[$t] find $i",
		      " -> ".$cb_stores{$ta}->get($i,COMBO_TEXT));
		$wp->set_active_iter($i);
	      }
	    } else {
	      debug "no CB_STORE for $ta";
	      $wp->set_active($h->{$t});
	    }
	}
	$wp=$gap->get_object($prefixe.'_ce_'.$ta) || $w{$prefixe.'_ce_'.$ta};
	if($wp) {
	    $w{$prefixe.'_ce_'.$t}=$wp;
	    if($cb_stores{$ta}) {
		debug "CB_STORE($t) ALIAS $ta changed";
		$wp->set_model($cb_stores{$ta});
	    }
	    my @we=grep { my (undef,$pr)=$_->class_path();$pr =~ /(yrtnE|Entry)/ } ($wp->get_children());
	    if(@we) {
		$we[0]->set_text($h->{$t});
		$w{$prefixe.'_x_'.$t}=$we[0];
	    } else {
		print STDERR $prefixe.'_ce_'.$t." : cannot find text widget\n";
	    }
	}
	debug "Key $t --> $ta : ".(defined($wp) ? "found widget $wp" : "NONE");
    }}
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
    my ($prefixe,$h,$oprefix,$seulement)=@_;
    $h->{'_modifie'}=($h->{'_modifie'} ? 1 : '');

    debug "Restricted search: ".join(',',keys %$seulement)
      if($seulement);
    for my $t (keys %$h) {
      if(!$seulement || $seulement->{$t}) {
	my $tgui=$t;
	$tgui =~ s/$oprefix$// if($oprefix);
	debug "Looking for widget <$tgui> in domain <$prefixe>";
	my $n;
	my $wp=$w{$prefixe.'_x_'.$tgui};
	if($wp) {
	    $n=$wp->get_text();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_t_'.$tgui};
	if($wp) {
	    my $buf=$wp->get_buffer;
	    $n=$buf->get_text($buf->get_start_iter,$buf->get_end_iter,1);
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_f_'.$tgui};
	if($wp) {
	    if($wp->get_action =~ /-folder$/i) {
		if(-d $wp->get_filename()) {
		    $n=$wp->get_filename();
		} else {
		    $n=$wp->get_current_folder();
		}
	    } else {
		$n=$wp->get_filename();
	    }
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_v_'.$tgui};
	if($wp) {
	    $n=$wp->get_active();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_s_'.$tgui};
	if($wp) {
	    $n=$wp->get_value();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_col_'.$tgui};
	if($wp) {
	    $n=$wp->get_color()->to_string();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_cb_'.$tgui};
	if($wp) {
	    $n=$wp->get_active();
	    $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_c_'.$tgui};
	if($wp) {
	  debug "Found combobox";
	  if($wp->get_model) {
	    if($wp->get_active_iter) {
	      $n=$wp->get_model->get($wp->get_active_iter,COMBO_ID);
	    } else {
	      debug "No active iter for combobox ".$prefixe.'_c_'.$tgui;
	      $n='';
	    }
	  } else {
	    $n=$wp->get_active();
	  }
	  $h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	  $h->{$t}=$n;
	}
      } else {
	debug "Skip widget <$t>";
      }
    }

    debug "Changes : $h->{'_modifie'}";
}

sub change_methode_impression {
    if($w{'pref_x_print_command_pdf'}) {
	my $m='';
	if($w{'pref_c_methode_impression'}->get_active_iter) {
	    $m=$w{'pref_c_methode_impression'}->get_model->get($w{'pref_c_methode_impression'}->get_active_iter,COMBO_ID);
	}
	$w{'pref_x_print_command_pdf'}->set_sensitive($m eq 'commande');
    }
}

sub edit_preferences {
    my $gap=read_glade('edit_preferences',
		       qw/pref_projet_tous pref_projet_annonce pref_x_print_command_pdf pref_c_methode_impression symboles_tree email_group_sendmail email_group_SMTP/);

    $w{'edit_preferences_manager'}=$gap;

    if($o{'conserve_taille'}) {
      if($o{'preferences_window_size'} &&
	 $o{'preferences_window_size'} =~ /^([0-9]+)x([0-9]+)$/) {
	$w{'edit_preferences'}->resize($1,$2);
      }
    }

    # tableau type/couleurs pour correction

    for my $t (grep { /^pref(_projet)?_[xfcv]_/ } (keys %w)) {
	delete $w{$t};
    }
    transmet_pref($gap,'pref',\%o);
    transmet_pref($gap,'pref_projet',$projet{'options'}) if($projet{'nom'});

    # projet ouvert -> ne pas changer localisation
    if($projet{'nom'}) {
	$w{'pref_f_rep_projets'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>'.sprintf(__"Project \"%s\" preferences",$projet{'nom'}).'</i>.');
    } else {
	$w{'pref_projet_tous'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>'.__("Project preferences").'</i>');
    }

    # anavailable options, managed by the filter:
    if($projet{'options'}->{'filter'}) {
      for my $k (("AMC::Filter::register::".$projet{'options'}->{'filter'})
		 ->forced_options()) {
      TYPES: for my $t (qw/c cb ce col f s t v x/) {
	  if(my $w=$gap->get_object("pref_projet_".$t."_".$k)) {
	    $w->set_sensitive(0);
	    last TYPES;
	  }
	}
      }
    }

    change_methode_impression();
}

sub closes_preferences {
  if($o{'conserve_taille'}) {
    my $dims=join('x',$w{'edit_preferences'}->get_size);
    if($dims ne $o{'preferences_window_size'}) {
      $o{'preferences_window_size'}=$dims;
      $o{'_modifie_ok'}=1;
    }
  }
  $w{'edit_preferences'}->destroy();
}

sub accepte_preferences {
  reprend_pref('pref',\%o);
  reprend_pref('pref_projet',$projet{'options'}) if($projet{'nom'});

  my %pm;
  my %gm;
  my @dgm;
  my %labels;

  if ($projet{'nom'}) {
    %pm=map { $_=>1 } (split(/,/,$projet{'options'}->{'_modifie'}));
    %gm=map { $_=>1 } (split(/,/,$o{'_modifie'}));
    @dgm=grep { /^defaut_/ } (keys %gm);

    for my $k (@dgm) {
      my $l=$w{'edit_preferences_manager'}->get_object('label_'.$k);
      $labels{$k}=$l->get_text() if($l);
      my $kp=$k;
      $kp =~ s/^defaut_//;
      $l=$w{'edit_preferences_manager'}->get_object('label_'.$kp);
      $labels{$kp}=$l->get_text() if($l);
    }
  }

  closes_preferences();

  if ($projet{'nom'}) {

    # Check if annotations are still valid (same options)

    my $changed=0;
    for(qw/annote_chsign taille_max_correction qualite_correction symboles_trait
	   symboles_indicatives annote_ps_nl annote_ecart/) {
      $changed=1 if($gm{$_});
    }
    for my $tag (qw/0_0 0_1 1_0 1_1/) {
      $changed=1 if($gm{"symbole_".$tag."_type"} || $gm{"symbole_".$tag."_color"});
    }
    for(qw/annote_position verdict verdict_q annote_rtl/) {
      $changed=1 if($pm{$_});
    }

    if($changed) {
      $projet{'_capture'}->begin_transaction('APch');
      $projet{'_capture'}->variable('annotate_source_change',time());
      $projet{'_capture'}->end_transaction('APch');
    }

    # Look at modified default values...

    debug "Modified (general): $o{'_modifie'}";
    debug "Modified (project): ".$projet{'options'}->{'_modifie'};
    debug "Labels: ".join(',',keys %labels);

    for my $k (@dgm) {
      my $kp=$k;
      $kp =~ s/^defaut_//;

      debug "Test G:$k / P:$kp";
      if ((!$pm{$kp}) && ($projet{'options'}->{$kp} ne $o{$k})) {
	# project option has NOT been modified, and the new
	# value of general default option is different from
	# project option. Ask the user for modifying also the
	# project option value
	$label_projet=$labels{$kp};
	$label_general=$labels{$k};

	debug "Ask user $label_general | $label_projet";

	if ($label_projet && $label_general) {
	  my $dialog = Gtk2::MessageDialog
	    ->new_with_markup($w{'main_window'},
			      'destroy-with-parent',
			      'question','yes-no',
			      sprintf(__("You modified \"<b>%s</b>\" value, which is the default value used when creating new projects. Do you want to change also \"<b>%s</b>\" for the opened <i>%s</i> project?"),
				      $label_general,$label_projet,$projet{'nom'}));
	  my $reponse=$dialog->run;
	  $dialog->destroy;

	  debug "Reponse: $reponse";

	  if ($reponse eq 'yes') {
	    # change also project option value
	    $projet{'options'}->{$kp}=$o{$k};
	    $projet{'options'}->{'_modifie'}.=",$kp";
	  }

	}
      }
    }
  }

  if ($projet{'nom'}) {
    for my $k (qw/note_min note_max note_grain/) {
      $projet{'options'}->{$k} =~ s/\s+//g;
    }
  }

  sauve_pref_generales();

  test_commandes();

  if (defined($projet{'options'}->{'_modifie'})
      && $projet{'options'}->{'_modifie'} =~ /\bseuil\b/) {
    if ($projet{'_capture'}->n_pages_transaction()>0) {
      # mise a jour de la liste diagnostic
      detecte_analyse();
    }
  }
}


sub sauve_pref_generales {
    debug "Saving general preferences...";

    if(pref_xx_ecrit(\%o,'AMC',$o_file)) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  __"Error writing to options file %s: %s"
		  ,$o_file,$!);
	$dialog->run;
	$dialog->destroy;
    } else {
	$o{'_modifie'}=0;
    }
}

sub annule_preferences {
    debug "Canceling preferences modification";
    closes_preferences();
}

sub file_maj {
    my (@f)=@_;
    my $present=1;
    my $oldest=0;
    for my $file (@f) {
	if($file && -f $file) {
	    if(-r $file) {
		my @s=stat($file);
		$oldest=$s[9] if($s[9]>$oldest);
	    } else {
		return('UNREADABLE');
	    }
	} else {
	    return('NOTFOUND');
	}
    }
    return(decode('UTF-8',strftime("%x %X",localtime($oldest))));
}

sub check_document {
    my ($filename,$k)=@_;
    $w{'but_'.$k}->set_sensitive(-f $filename);
}

sub state_image {
  my ($k,$stock)=@_;
  $w{'stateimg_'.$k}->set_from_stock($stock,
				     GTK_ICON_SIZE_BUTTON)
    if($w{'stateimg_'.$k});
  $w{'state_'.$k}->set_icon_from_stock(GTK_ENTRY_ICON_PRIMARY,$stock)
    if($w{'state_'.$k});
}

sub detecte_documents {
    check_document(absolu($projet{'options'}->{'docs'}->[0]),'question');
    check_document(absolu($projet{'options'}->{'docs'}->[1]),'solution');
    my $s=file_maj(map { absolu($projet{'options'}->{'docs'}->[$_])
		   } (0..2));
    my $ok='gtk-yes';
    if($s eq 'UNREADABLE') {
	$s=__("Working documents are not readable");
	$ok='gtk-dialog-error';
    } elsif($s eq 'NOTFOUND') {
	$s=__("No working documents");
	$ok='gtk-dialog-error';
    } else {
	$s=__("Working documents last update:")." ".$s;
    }
    state_image('docs',$ok);
    $w{'state_docs'}->set_text($s);
}

sub show_document {
    my ($sel)=@_;
    my $f=absolu($projet{'options'}->{'docs'}->[$sel]);
    debug "Looking at $f...";
    commande_parallele($o{'pdf_viewer'},absolu($projet{'options'}->{'docs'}->[$sel]));
}

sub show_question {
    show_document(0);
}

sub show_solution {
    show_document(1);
}

sub detecte_mep {
    $projet{'_layout'}->begin_read_transaction('LAYO');
    $projet{'_mep_defauts'}={$projet{'_layout'}->defects()};
    my $c=$projet{'_layout'}->pages_count;
    $projet{'_layout'}->end_transaction('LAYO');
    my @def=(keys %{$projet{'_mep_defauts'}});
    if(@def) {
	$w{'button_mep_warnings'}->show();
    } else {
	$w{'button_mep_warnings'}->hide();
    }
    $w{'onglet_saisie'}->set_sensitive($c>0);
    my $s;
    my $ok='gtk-yes';
    if($c<1) {
	$s=__("No layout");
	$ok='gtk-dialog-error';
    } else {
	$s=sprintf(__("Processed %d pages"),
		   $c);
	if(@def) {
	    $s.=", ".__("but some defects were detected.");
	    $ok='gtk-dialog-question';
	} else {
	    $s.='.';
	}
    }
    $w{'state_layout'}->set_text($s);
    state_image('layout',$ok);
}

my %defect_text=
  (
   'NO_NAME'=>__("The \\namefield command is not used. Writing subjects without name field is not recommended"),
   'SEVERAL_NAMES'=>__("The \\namefield command is used several times for the same subject. This should not be the case, as each student should write his name only once"),
   'NO_BOX'=>__("No box to be ticked"),
   'DIFFERENT_POSITIONS'=>__("The corner marks and binary boxes are not at the same location on all pages"),
  );

sub mep_warnings {
    my $m='';
    my @def=(keys %{$projet{'_mep_defauts'}});
    if(@def) {
      $m=__("Some potential defects were detected for this subject. Correct them in the source and update the working documents.");
      for my $k (keys %defect_text) {
	my $dd=$projet{'_mep_defauts'}->{$k};
	if($dd) {
	  if($k eq 'DIFFERENT_POSITIONS') {
	    $m.="\n<b>".$defect_text{$k}."</b> ".
	      sprintf(__('(See for exemple pages %s and %s)'),
		      pageids_string($dd->{'student_a'},$dd->{'page_a'}),
		      pageids_string($dd->{'student_b'},$dd->{'page_b'})).'.';
	  } else {
	    my @e=sort { $a <=> $b } (@{$dd});
	    if(@e) {
	      $m.="\n<b>".$defect_text{$k}."</b> ".
		sprintf(__('(Concerns %1$d sheets, see for exemple sheet %2$d)'),1+$#e,$e[0]).'.';
	    }
	  }
	}
      }
    } else {
	# should not be possible to go there...
	return();
    }
    my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'warning','ok',
			  $m
	);
    $dialog->run;
    $dialog->destroy;

}

sub clear_processing {
  my ($steps)=@_;
  my $next='';
  my %s=();
  for my $k (qw/doc mep capture mark assoc/) {
    if($steps =~ /\b$k:/) {
      $next=1;
      $s{$k}=1;
    } elsif($next || $steps =~ /\b$k\b/) {
      $s{$k}=1;
    }
  }

  if($s{'doc'}) {
    for (0,1,2) {
      my $f=absolu($projet{'options'}->{'docs'}->[$_]);
      unlink($f) if(-f $f);
    }
    detecte_documents();
  }

  delete($s{'doc'});
  return() if(!%s);

  # data to remove...

  $projet{'_data'}->begin_transaction('CLPR');

  if($s{'mep'}) {
    $projet{_layout}->clear_all;
  }

  if($s{'capture'}) {
    $projet{_capture}->clear_all;
  }

  if($s{'mark'}) {
    $projet{'_scoring'}->clear_strategy;
    $projet{'_scoring'}->clear_score;
  }

  if($s{'assoc'}) {
    $projet{_association}->clear;
  }

  $projet{'_data'}->end_transaction('CLPR');

  # files to remove...

  if($s{'capture'}) {
    # remove zooms
    remove_tree(absolu('%PROJET/cr/zooms'),
		{'verbose'=>0,'safe'=>1,'keep_root'=>1});
    # remove namefield extractions and page layout image
    my $crdir=absolu('%PROJET/cr');
    opendir(my $dh,$crdir);
    my @cap_files=grep { /^(name-|page-)/ } readdir($dh);
    closedir($dh);
    for(@cap_files) {
      unlink "$crdir/$_";
    }
  }

  # update gui...

  if($s{'mep'}) {
    detecte_mep();
  }
  if($s{'capture'}) {
    detecte_analyse();
  }
  if($s{'mark'}) {
    noter_resultat();
  }
  if($s{'assoc'}) {
    assoc_state();
  }
}

sub update_analysis_summary {
  my $n=$projet{'_capture'}->n_pages;

  my %r=$projet{'_capture'}->counts;

  $r{'npages'}=$n;

  my $failed_nb=$projet{'_capture'}
    ->sql_single($projet{'_capture'}->statement('failedNb'));

  $w{'onglet_notation'}->set_sensitive($n>0);

  # resume

  my $tt='';
  if ($r{'incomplete'}) {
    $tt=sprintf(__"Data capture from %d complete papers and %d incomplete papers",$r{'complete'},$r{'incomplete'});
    state_image('capture','gtk-dialog-error');
    $w{'button_show_missing'}->show();
  } elsif ($r{'complete'}) {
    $tt=sprintf(__("Data capture from %d complete papers"),$r{'complete'});
    state_image('capture','gtk-yes');
    $w{'button_show_missing'}->hide();
  } else {
    # TRANSLATORS: this text points out that no data capture has been made yet.
    $tt=sprintf(__"No data");
    state_image('capture','gtk-dialog-error');
    $w{'button_show_missing'}->hide();
  }
  $w{'state_capture'}->set_text($tt);

  if ($failed_nb<=0) {
    if($r{'complete'}) {
      $tt=__"All scans were properly recognized.";
      state_image('unrecognized','gtk-yes');
    } else {
      $tt="";
      state_image('unrecognized',undef);
    }
    $w{'button_unrecognized'}->hide();
  } else {
    $tt=sprintf(__"%d scans were not recognized.",$failed_nb);
    state_image('unrecognized','gtk-dialog-question');
    $w{'button_unrecognized'}->show();
  }
  $w{'state_unrecognized'}->set_text($tt);

  return(\%r);
}

sub detecte_analyse {
    my (%oo)=(@_);
    my $iter;
    my $row;

    $diag_store->clear;

    $w{'commande'}->show();
    my $av_text=$w{'avancement'}->get_text();
    my $frac;
    my $total;
    my $i;

    $projet{'_capture'}->begin_read_transaction('ADCP');

    my $summary=$projet{'_capture'}
      ->summaries('darkness_threshold'=>$projet{'options'}->{'seuil'},
		  'sensitivity_threshold'=>$o{'seuil_sens'},
		  'mse_threshold'=>$o{'seuil_eqm'});

    $total=$#{$summary}+1;
    $i=0;
    $frac=0;
    if($total>0) {
      $w{'avancement'}->set_text(__"Looking for analysis...");
      Gtk2->main_iteration while ( Gtk2->events_pending );
    }
    for my $p (@$summary) {
      $iter=$diag_store->append;
      $diag_store->set($iter,
		       DIAG_ID,pageids_string($p->{'student'},$p->{'page'},$p->{'copy'}),
		       DIAG_ID_STUDENT,$p->{'student'},
		       DIAG_ID_PAGE,$p->{'page'},
		       DIAG_ID_COPY,$p->{'copy'},
		       DIAG_ID_BACK,$p->{'color'},
		       DIAG_EQM,$p->{'mse_string'},
		       DIAG_EQM_BACK,$p->{'mse_color'},
		       DIAG_MAJ,format_date($p->{'timestamp'}),
		       DIAG_DELTA,$p->{'sensitivity_string'},
		       DIAG_DELTA_BACK,$p->{'sensitivity_color'},
		      );
      $i++;
      if($i/$total>=$frac+.05) {
	$frac=$i/$total;
	$w{'avancement'}->set_fraction($frac);
	Gtk2->main_iteration while ( Gtk2->events_pending );
      }
    }

    $w{'avancement'}->set_text($av_text);
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    $w{'commande'}->hide() if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    my $r=update_analysis_summary();

    $projet{'_capture'}->end_transaction('ADCP');

    # dialogue apprentissage :

    if($oo{'apprend'}) {
	dialogue_apprentissage('SAISIE_AUTO','','',0,
			       __("Automatic data capture now completed.")." "
			       .($r->{'incomplet'}>0 ? sprintf(__("It is not complete (missing pages from %d papers).")." ",$r->{'incomplet'}) : '')
			       .__("You can analyse data capture quality with some indicators values in analysis list:")
			       ."\n"
			       .sprintf(__"- <b>%s</b> represents positioning gap for the four corner marks. Great value means abnormal page distortion.",__"MSE")
			       ."\n"
			       .sprintf(__"- great values of <b>%s</b> are seen when darkness ratio is very close to the threshold for some boxes.",__"sensitivity")
			       ."\n"
			       .sprintf(__"You can also look at the scan adjustment (<i>%s</i>) and ticked and unticked boxes (<i>%s</i>) using right-click on lines from table <i>%s</i>.",__"page adjustment",__"boxes zooms",__"Diagnosis")
			       );
    }

}

sub show_missing_pages {
  $projet{'_capture'}->begin_read_transaction('cSMP');
  my %r=$projet{'_capture'}->counts;
  $projet{'_capture'}->end_transaction('cSMP');

  my $l='';
  my @sc=();
  for my $p (@{$r{'missing'}}) {
    if($sc[0] != $p->{'student'} || $sc[1] != $p->{'copy'}) {
      @sc=($p->{'student'},$p->{'copy'});
      $l.="\n";
    }
    $l.="  ".pageids_string($p->{'student'},
			   $p->{'page'},$p->{'copy'});
  }

  my $dialog = Gtk2::MessageDialog
    ->new_with_markup
      ($w{'main_window'},
       'destroy-with-parent',
       'info','ok',
       "<b>".(__"Pages that miss data capture to complete students sheets:")."</b>"
       .$l
      );
  $dialog->run;
  $dialog->destroy;
}

sub update_unrecognized {
  $projet{'_capture'}->begin_read_transaction('UNRC');
  my $failed=$projet{'_capture'}->dbh
    ->selectall_arrayref($projet{'_capture'}->statement('failedList'),
			 {Slice => {}});
  $projet{'_capture'}->end_transaction('UNRC');

  $inconnu_store->clear;
  for my $ff (@$failed) {
    my $iter=$inconnu_store->append;
    my $f=$ff->{'filename'};
    $f =~ s:.*/::;
    my (undef,undef,$scan_n)=splitpath(absolu($ff->{'filename'}));
    my $preproc_file=absolu('%PROJET/cr/diagnostic')."/".$scan_n.".png";
    $inconnu_store->set($iter,
			INCONNU_SCAN,$f,
			INCONNU_FILE,$ff->{'filename'},
			INCONNU_TIME,format_date($ff->{'timestamp'}),
			INCONNU_TIME_N,$ff->{'timestamp'},
			INCONNU_PREPROC,$preproc_file,
		       );
  }
}

sub open_unrecognized {

  my $dialog=read_glade('unrecognized',
			qw/inconnu_tree scan_area preprocessed_area
			   inconnu_hpaned inconnu_vpaned
			   main_recog state_scanrecog ur_frame_scan/);

  # make state entries with same background color as around...
  my $col=$w{'ur_frame_scan'}->style()->bg('normal');
  for my $s (qw/normal insensitive/) {
    for my $k (qw/scanrecog/) {
      $w{'state_'.$k}->modify_base($s,$col);
    }
  }

  for (qw/scan preprocessed/) {
    AMC::Gui::PageArea::add_feuille($w{$_.'_area'});
    $w{$_.'_area'}->signal_connect('expose_event'=>\&AMC::Gui::PageArea::expose_drawing);
  }

  $w{'inconnu_tree'}->set_model($inconnu_store);

  $renderer=Gtk2::CellRendererText->new;
  $column = Gtk2::TreeViewColumn->new_with_attributes ("scan",
						       $renderer,
						       text=> INCONNU_SCAN);
  $w{'inconnu_tree'}->append_column ($column);
  $column->set_sort_column_id(INCONNU_SCAN);

  $renderer=Gtk2::CellRendererText->new;
  $column = Gtk2::TreeViewColumn->new_with_attributes ("date",
						       $renderer,
						       text=> INCONNU_TIME);
  $w{'inconnu_tree'}->append_column ($column);
  $column->set_sort_column_id(INCONNU_TIME_N);

  update_unrecognized();

  $w{'inconnu_tree'}->get_selection->set_mode(GTK_SELECTION_MULTIPLE);
  $w{'inconnu_tree'}->get_selection->signal_connect("changed",\&unrecognized_line);
  $w{'inconnu_tree'}->get_selection->select_iter($inconnu_store->get_iter_first);

  $w{'inconnu_vpaned'}->child1_shrink(0);

  $w{'inconnu_hpaned'}->child1_resize(1);
  $w{'inconnu_hpaned'}->child2_resize(1);
}

sub unrecognized_line {
  my @sel=$w{'inconnu_tree'}->get_selection->get_selected_rows;
  if(@sel) {
    $w{'inconnu_tree'}->scroll_to_cell($sel[0]);
    my $iter=$inconnu_store->get_iter($sel[0]);
    my $scan=absolu($inconnu_store->get($iter,INCONNU_FILE));
    if(-f $scan) {
      $w{'scan_area'}->set_image($scan);
    } else {
      debug_and_stderr "Scan not found: $scan";
      $w{'scan_area'}->set_image('NONE');
    }

    my $preproc=$inconnu_store->get($iter,INCONNU_PREPROC);
    if(-f $preproc) {
      $w{'preprocessed_area'}->set_image($preproc);
    } else {
      $w{'preprocessed_area'}->set_image('NONE');
    }

    if($w{'scan_area'}->get_image) {
      my $scan_n=$scan;
      $scan_n =~ s:^.*/::;
      state_image('scanrecog','gtk-dialog-question');
      $w{'state_scanrecog'}->set_text($scan_n);
    } else {
      state_image('scanrecog','gtk-dialog-error');
      $w{'state_scanrecog'}->set_text(sprintf((__"Error loading scan %s"),$scan));
    }
  } else {
    state_image('scanrecog','gtk-dialog-question');
    $w{'state_scanrecog'}->set_text(__"No scan selected");
  }
}

sub unrecognized_next {
  my (@sel)=@_;
  @sel=$w{'inconnu_tree'}->get_selection->get_selected_rows
    if(!@sel);
  my $iter;
  if(@sel) {
    $iter=$inconnu_store->iter_next($inconnu_store->get_iter($sel[$#sel]));
  }
  $iter=$inconnu_store->get_iter_first if(!$iter);

  $w{'inconnu_tree'}->get_selection->unselect_all;
  $w{'inconnu_tree'}->get_selection->select_iter($iter);
}

sub unrecognized_prev {
  my @sel=$w{'inconnu_tree'}->get_selection->get_selected_rows;
  my $iter;
  if(@sel) {
    my $p=$inconnu_store->get_path($inconnu_store->get_iter($sel[0]));
    if($p->prev) {
      $iter=$inconnu_store->get_iter($p);
    } else {
      $iter='';
    }
  }
  $iter=$inconnu_store->get_iter_first if(!$iter);

  $w{'inconnu_tree'}->get_selection->unselect_all;
  $w{'inconnu_tree'}->get_selection->select_iter($iter);
}

sub unrecognized_delete {
  my @iters;
  my @sel=($w{'inconnu_tree'}->get_selection->get_selected_rows);
  return if(!@sel);

  $projet{'_capture'}->begin_transaction('rmUN');
  for my $s (@sel) {
    my $iter=$inconnu_store->get_iter($s);
    my $file=$inconnu_store->get($iter,INCONNU_FILE);
    $projet{'_capture'}->statement('deleteFailed')->execute($file);
    unlink absolu($file);
    push @iters,$iter;
  }
  unrecognized_next(@sel);
  for(@iters) { $inconnu_store->remove($_); }
  update_analysis_summary();
  $projet{'_capture'}->end_transaction('rmUN');
}

sub analyse_diagnostic {
  my @sel=$w{'inconnu_tree'}->get_selection->get_selected_rows;
  if(@sel) {
    my $iter=$inconnu_store->get_iter($sel[0]);
    my $scan=absolu($inconnu_store->get($iter,INCONNU_FILE));
    my $diagnostic_file=$inconnu_store->get($iter,INCONNU_PREPROC);

    if(!-f $diagnostic_file) {
      analyse_call('f'=>[$scan],
		   'text'=>__("Making diagnostic image..."),
		   'progres'=>'diagnostic',
		   'diagnostic'=>1,
		   'fin'=>sub {
		     unrecognized_line();
		   },
		  );
    }
  }
}

sub set_source_tex {
    my ($importe)=@_;

    importe_source() if($importe);
    valide_source_tex();
}

sub liste_montre_nom {
    my $dialog = Gtk2::MessageDialog
	->new($w{'main_window'},
	      'destroy-with-parent',
	      'info','ok',
	      __"Names list file for this project is:\n%s",
	      ($projet{'options'}->{'listeetudiants'} ? absolu($projet{'options'}->{'listeetudiants'}) : __"(no file)" ));
    $dialog->run;
    $dialog->destroy;
}

sub valide_source_tex {
    $projet{'options'}->{'_modifie'}=1;
    debug "* valide_source_tex";

    $w{'state_src'}->set_text(absolu($projet{'options'}->{'texsrc'}));

    if(!$projet{'options'}->{'filter'}) {
      $projet{'options'}->{'filter'}=
	best_filter_for_file(absolu($projet{'options'}->{'texsrc'}));
    }

    detecte_documents();
}

my $modeles_store;

sub charge_modeles {
    my ($store,$parent,$rep)=@_;

    return if(! -d $rep);

    my @all;
    my @ms;
    my @subdirs;

    if(opendir(DIR,$rep)) {
	@all=readdir(DIR);
	@ms=grep { /\.tgz$/ && -f $rep."/$_" } @all;
	@subdirs=grep { -d $rep."/$_" && ! /^\./ } @all;
	closedir DIR;
    } else {
	debug("MODELS : Can't open directory $rep : $!");
    }

    for my $sd (sort { $a cmp $b } @subdirs) {
	my $nom=$sd;
	my $desc_text='';

	my $child = $store->append($parent);
	if(-f $rep."/$sd/directory.xml") {
	    my $d=XMLin($rep."/$sd/directory.xml");
	    $nom=$d->{'title'} if($d->{'title'});
	    $desc_text=$d->{'text'} if($d->{'text'});
	}
	$store->set($child,MODEL_NOM,$nom,
		    MODEL_PATH,'',
		    MODEL_DESC,$desc_text);
	charge_modeles($store,$child,$rep."/$sd");
    }

    for my $m (sort { $a cmp $b } @ms) {
	my $child = $store->append($parent);

	my $nom=$m;
	$nom =~ s/\.tgz$//i;
	my $desc_text=__"(no description)";
	my $tar=Archive::Tar->new($rep."/$m");
	my @desc=grep { /description.xml$/ } ($tar->list_files());
	if($desc[0]) {
	    my $d=XMLin($tar->get_content($desc[0]),'SuppressEmpty'=>'');
	    $nom=$d->{'title'} if($d->{'title'});
	    $desc_text=$d->{'text'} if($d->{'text'});
	}
	debug "Adding model $m";
	debug "NAME=$nom DESC=$desc_text";
	$store->set($child,
		    MODEL_NOM,$nom,
		    MODEL_PATH,$rep."/$m",
		    MODEL_DESC,$desc_text);
    }
}

sub modele_dispo {
    my $iter=$w{'modeles_liste'}->get_selection()->get_selected();
    if($iter) {
	$w{'model_choice_button'}->set_sensitive($modeles_store->get($iter,MODEL_PATH) ? 1 : 0);
    } else {
	debug "No iter for models selection";
    }
}

sub path_from_tree {
    my ($store,$view,$f)=@_;
    my $i=undef;

    return(undef) if(!$f);

    my $d='';

    for my $pp (split(m:/:,$f)) {
	my $ipar=$i;
	$d.='/' if($d);
	$d.=$pp;
	$i=model_id_to_iter($store,TEMPLATE_FILES_PATH,$d);
	if(!$i) {
	    $i=$store->append($ipar);
	    $store->set($i,TEMPLATE_FILES_PATH,$d,
			TEMPLATE_FILES_FILE,$pp);
	}
    }

    $view->expand_to_path($store->get_path($i));
    return($i);
}

sub template_add_file {
    my ($store,$view,$f)=@_;

    # removes local part

    my $p_dir=absolu('%PROJET/');
    if($f =~ s:^\Q$p_dir\E::) {
	my $i=path_from_tree($store,$view,$f);
	return($i);
    } else {
	debug "Trying to add non local file: $f (local dir is $p_dir)";
	return(undef);
    }
}

sub make_template {

    if(!$projet{'nom'}) {
	debug "Make template: no opened project";
	return();
    }

    my $gt=read_glade('make_template',
		      qw/template_files_tree template_name template_file_name template_description template_file_name_warning mt_ok
			template_description_scroll template_files_scroll/);

    $w{'template_file_name_style'} = $w{'template_file_name'}->get_modifier_style->copy;

    $template_files_store->clear;

    $w{'template_files_tree'}->set_model($template_files_store);
	my $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is a column title for the list of files to be included in a template being created.
	my $column = Gtk2::TreeViewColumn->new_with_attributes(__"file",
							       $renderer,
							       text=> TEMPLATE_FILES_FILE );
    $w{'template_files_tree'}->append_column ($column);
    $w{'template_files_tree'}->get_selection->set_mode("multiple");

    # Detects files to include

    template_add_file($template_files_store,$w{'template_files_tree'},
		      absolu($projet{'options'}->{'texsrc'}));
    template_add_file($template_files_store,$w{'template_files_tree'},
		      fich_options($projet{'nom'}));

    for (qw/description files/) {
      $w{'template_'.$_.'_scroll'}->set_policy('automatic','automatic');
    }

    # Waits for action

    $resp=$w{'make_template'}->run();

    if($resp eq "1") {

	projet_check_and_save();

	# Creates template

	my $tfile=$o{'rep_modeles'}.'/'.$w{'template_file_name'}->get_text().".tgz";
	my $tar=Archive::Tar->new();
	$template_files_store->foreach(\&add_to_archive,[$tar]);

	# Description

	my $buf=$w{'template_description'}->get_buffer;

	my $desc='';
	my $writer=new XML::Writer(OUTPUT=>\$desc,ENCODING=>'utf-8');
	$writer->xmlDecl("UTF-8");
	$writer->startTag('description');
	$writer->dataElement('title',$w{'template_name'}->get_text());
	$writer->dataElement('text',$buf->get_text($buf->get_start_iter,$buf->get_end_iter,1));
	$writer->endTag('description');
	$writer->end();

	$tar->add_data('description.xml',encode_utf8($desc));

	$tar->write($tfile,COMPRESS_GZIP);
    }

    $w{'make_template'}->destroy;
}

sub add_to_archive {
    my ($store,$path,$iter,$data)=@_;
    my ($tar)=@$data;

    my $f=$store->get($iter,TEMPLATE_FILES_PATH);
    my $af=absolu("%PROJET/$f");

    return(0) if($f eq 'description.xml');

    if(-f $af) {
	debug "Adding to template archive: $f\n";
	my $tf=Archive::Tar::File->new( file => $af);
	$tf->rename($f);
	$tar->add_files($tf);
    }

    return(0);
}

sub template_filename_verif {
    restricted_check($w{'template_file_name'},$w{'template_file_name_style'},
		     $w{'template_file_name_warning'},"a-zA-Z0-9_+-");
    my $t=$w{'template_file_name'}->get_text();
    my $tfile=$o{'rep_modeles'}.'/'.$t.".tgz";
    $w{'mt_ok'}->set_sensitive($t && !-e $tfile);
}

sub make_template_add {
    my $fs=Gtk2::FileSelection->new(__"Add files to template");
    $fs->set_filename(absolu('%PROJET/'));
    $fs->set_select_multiple(1);
    $fs->hide_fileop_buttons;

    my $err=0;
    my $resp=$fs->run();
    if($resp eq 'ok') {
	for my $f ($fs->get_selections()) {
	    $err++
		if(!defined(template_add_file($template_files_store,$w{'template_files_tree'},$f)));
	}
    }
    $fs->destroy();

    if($err) {
	my $dialog=Gtk2::MessageDialog
	    ->new_with_markup($w{'make_template'},
			      'destroy-with-parent',
			      'error','ok',
			      __("When making a template, you can only add files that are within the project directory."));
	$dialog->run();
	$dialog->destroy();
    }
}

sub make_template_del {
    my @i=();
    for my $path ($w{'template_files_tree'}->get_selection->get_selected_rows) {
	push @i,$template_files_store->get_iter($path);
    }
    for(@i) {
	$template_files_store->remove($_);
    }
}

sub n_fich {
    my ($dir)=@_;

    if(opendir(NFICH,$dir)) {
	my @f=grep { ! /^\./ } readdir(NFICH);
	closedir(NFICH);

	return(1+$#f,"$dir/$f[0]");
    } else {
	debug("N_FICH : Can't open directory $dir : $!");
 	return(0);
    }
}

sub unzip_to_temp {
  my ($file)=@_;

  my $temp_dir = tempdir( DIR=>tmpdir(),CLEANUP => 1 );
  my $error=0;

  my @cmd;

  if($file =~ /\.zip$/i) {
    @cmd=("unzip","-d",$temp_dir,$file);
  } else {
    @cmd=("tar","-x","-v","-z","-f",$file,"-C",$temp_dir);
  }

  debug "Extracting archive files\nFROM: $file\nWITH: ".join(' ',@cmd);
  if(open(UNZIP,"-|",@cmd) ) {
    while(<UNZIP>) {
      debug $_;
    }
    close(UNZIP);
  } else {
    $error=$!;
  }

  return($temp_dir,$error);
}



sub source_latex_choisir {

    my %oo=@_;
    my $texsrc='';

    if(!$oo{'nom'}) {
	debug "ERR: Empty name for source_latex_choisir";
	return(0,'');
    }

    if(-e $o{'rep_projets'}."/".$oo{'nom'}) {
	debug "ERR: existing project directory $oo{'nom'} for source_latex_choisir";
	return(0,'');
    }

    my %bouton=();

    if($oo{'type'}) {
	$bouton{$oo{'type'}}=1;
    } else {

	# fenetre de choix du source latex

	my $gap=read_glade('source_latex_dialog');

	my $dialog=$gap->get_object('source_latex_dialog');

	my $reponse=$dialog->run();

	for(qw/new choix vide zip/) {
	    $bouton{$_}=$gap->get_object('sl_type_'.$_)->get_active();
	    debug "Bouton $_" if($bouton{$_});
	}

	$dialog->destroy();

	debug "RESPONSE=$reponse";

	return(0,'') if($reponse!=10);
    }

    # actions apres avoir choisi le type de source latex a utiliser

    if($bouton{'new'}) {

	# choix d'un modele

	$gap=read_glade('source_latex_modele',
			qw/modeles_liste modeles_description model_choice_button mlist_separation/);

	$modeles_store = Gtk2::TreeStore->new('Glib::String',
					      'Glib::String',
					      'Glib::String');

	charge_modeles($modeles_store,undef,$o{'rep_modeles'}) if($o{'rep_modeles'});

	charge_modeles($modeles_store,undef,amc_specdir('models'));

	$w{'modeles_liste'}->set_model($modeles_store);
	my $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is a column name for the list of available templates, when creating a new project based on a template.
	my $column = Gtk2::TreeViewColumn->new_with_attributes(__"template",
							       $renderer,
							       text=> MODEL_NOM );
	$w{'modeles_liste'}->append_column ($column);
	$w{'modeles_liste'}->get_selection->signal_connect("changed",\&source_latex_mmaj);

	$w{'mlist_separation'}->set_position(.5*$w{'mlist_separation'}->get_property('max-position'));
	$w{'mlist_separation'}->child1_resize(1);
	$w{'mlist_separation'}->child2_resize(1);

	$reponse=$w{'source_latex_modele'}->run();

	debug "Dialog modele : $reponse";

	# le modele est choisi : l'installer

	my $mod;

	if($reponse) {
	    my $iter=$w{'modeles_liste'}->get_selection()->get_selected();
	    $mod=$modeles_store->get($iter,MODEL_PATH) if($iter);
	}

	$w{'source_latex_modele'}->destroy();

	return(0,'') if($reponse!=10);

	if($mod) {
	    debug "Installing model $mod";
	    return(source_latex_choisir('type'=>'zip','fich'=>$mod,
					'decode'=>1,'nom'=>$oo{'nom'}));
	} else {
	    debug "No model";
	    return(0,'');
	}

    } elsif($bouton{'choix'}) {

	# choisir un fichier deja present

	$gap=read_glade('source_latex_choix');

	$w{'source_latex_choix'}->set_current_folder($home_dir);

	# default filter: all possible source files

	my $filtre_all=Gtk2::FileFilter->new();
	$filtre_all->set_name(__"All source files");
	for my $m (@filter_modules) {
	  for my $p ("AMC::Filter::register::$m"->file_patterns) {
	    $filtre_all->add_pattern($p);
	  }
	}
	$w{'source_latex_choix'}->add_filter($filtre_all);

	# filters for each filter module

	for my $m (@filter_modules) {
	  my $f=Gtk2::FileFilter->new();
# TRANSLATORS: This is the label of a choice in a menu to select only files that corresponds to a particular format (which can be LaTeX or Plain for example). %s will be replaced by the name of the format.
	  my @pat=();
	  for my $p ("AMC::Filter::register::$m"->file_patterns) {
	    push @pat,$p;
	    $f->add_pattern($p);
	  }
	  $f->set_name(sprintf(__("%s files"),
			       "AMC::Filter::register::$m"->name())
		       .' ('.join(', ',@pat).')');
	  $w{'source_latex_choix'}->add_filter($f);
	}

	#

	$reponse=$w{'source_latex_choix'}->run();

	my $f=$w{'source_latex_choix'}->get_filename();

	$w{'source_latex_choix'}->destroy();

	return(0,'') if($reponse!=10);

	$texsrc=relatif($f,$oo{'nom'});
	debug "Source LaTeX $f";

    } elsif($bouton{'zip'}) {

	my $fich;

	if($oo{'fich'}) {
	    $fich=$oo{'fich'};
	} else {

	    # choisir un fichier ZIP

	    $gap=read_glade('source_latex_choix_zip');

	    $w{'source_latex_choix_zip'}->set_current_folder($home_dir);

	    my $filtre_zip=Gtk2::FileFilter->new();
	    $filtre_zip->set_name(__"Archive (zip, tgz)");
	    $filtre_zip->add_pattern("*.zip");
	    $filtre_zip->add_pattern("*.tar.gz");
	    $filtre_zip->add_pattern("*.tgz");
	    $filtre_zip->add_pattern("*.TGZ");
	    $filtre_zip->add_pattern("*.ZIP");
	    $w{'source_latex_choix_zip'}->add_filter($filtre_zip);

	    $reponse=$w{'source_latex_choix_zip'}->run();

	    $fich=$w{'source_latex_choix_zip'}->get_filename();

	    $w{'source_latex_choix_zip'}->destroy();

	    return(0,'') if($reponse!=10);
	}

	# cree un repertoire temporaire pour dezipper

	my ($temp_dir,$rv)=unzip_to_temp($fich);

	my ($n,$suivant)=n_fich($temp_dir);

	if($rv || $n==0) {
	    my $dialog = Gtk2::MessageDialog
		->new_with_markup($w{'main_window'},
				  'destroy-with-parent',
				  'error','ok',
				  sprintf(__"Nothing extracted from archive %s. Check it.",$fich));
	    $dialog->run;
	    $dialog->destroy;
	    return(0,'');
	} else {
	    # unzip OK
	    # vire les repertoires intermediaires :

	    while($n==1 && -d $suivant) {
		debug "Changing root directory : $suivant";
		$temp_dir=$suivant;
		($n,$suivant)=n_fich($temp_dir);
	    }

	    # bouge les fichiers la ou il faut

	    my $hd=$o{'rep_projets'}."/".$oo{'nom'};

	    mkdir($hd) if(! -e $hd);

	    my @archive_files;

	    if(opendir(MVR,$temp_dir)) {
		@archive_files=grep { ! /^\./ } readdir(MVR);
		closedir(MVR);
	    } else {
		debug("ARCHIVE : Can't open $temp_dir : $!");
	    }

	    my $latex;

	    for my $ff (@archive_files) {
		debug "Moving to project: $ff";
		if($ff =~ /\.tex$/i) {
		    $latex=$ff;
		    if($oo{'decode'}) {
			debug "Decoding $ff...";
			move("$temp_dir/$ff","$temp_dir/$ff.0enc");
			copy_latex("$temp_dir/$ff.0enc","$temp_dir/$ff");
		    }
		}
		if(system("mv","$temp_dir/$ff","$hd/$ff") != 0) {
		    debug "ERR: Move failed: $temp_dir/$ff --> $hd/$ff -- $!";
		    debug "(already exists)" if(-e "$hd/$ff");
		}
	    }

	    if($latex) {
		$texsrc="%PROJET/$latex";
		debug "LaTeX found : $latex";
	    }

	    return(2,$texsrc);
	}

    } elsif($bouton{'vide'}) {

      my $hd=$o{'rep_projets'}."/".$oo{'nom'};

      mkdir($hd) if(! -e $hd);

      $texsrc='source.tex';
      my $sl="$hd/$texsrc";

    } else {
      return(0,'');
    }

    return(1,$texsrc);

}

sub source_latex_mmaj {
    my $iter=$w{'modeles_liste'}->get_selection()->get_selected();
    my $desc='';

    $desc=$modeles_store->get($iter,MODEL_DESC) if($iter);
    $w{'modeles_description'}->get_buffer->set_text($desc);
}


# copie en changeant eventuellement d'encodage
sub copy_latex {
    my ($src,$dest)=@_;
    # 1) reperage du inputenc dans le source
    my $i='';
    open(SRC,$src);
  LIG: while(<SRC>) {
      s/%.*//;
      if(/\\usepackage\[([^\]]*)\]\{inputenc\}/) {
	  $i=$1;
	  last LIG;
      }
  }
    close(SRC);

    my $ie=get_enc($i);
    my $id=get_enc($o{'encodage_latex'});
    if($ie && $id && $ie->{'iso'} ne $id->{'iso'}) {
	debug "Reencoding $ie->{'iso'} => $id->{'iso'}";
	open(SRC,"<:encoding($ie->{'iso'})",$src) or return('');
	open(DEST,">:encoding($id->{'iso'})",$dest) or close(SRC),return('');
	while(<SRC>) {
	    chomp;
	    s/\\usepackage\[([^\]]*)\]\{inputenc\}/\\usepackage[$id->{'inputenc'}]{inputenc}/;
	    print DEST "$_\n";
	}
	close(DEST);
	close(SRC);
	return(1);
    } else {
	return(copy($src,$dest));
    }
}

sub importe_source {
    my ($fxa,$fxb,$fb) = splitpath($projet{'options'}->{'texsrc'});
    my $dest=absolu($fb);

    # fichier deja dans le repertoire projet...
    return() if(is_local($projet{'options'}->{'texsrc'},1));

    if(-f $dest) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','yes-no',
		  __("File %s already exists in project directory: do you wnant to replace it?")." "
		  .__("Click yes to replace it and loose pre-existing contents, or No to cancel source file import."),$fb);
	my $reponse=$dialog->run;
	$dialog->destroy;

	if($reponse eq 'no') {
	    return(0);
	}
    }

    if(copy_latex(absolu($projet{'options'}->{'texsrc'}),$dest)) {
	$projet{'options'}->{'texsrc'}=relatif($dest);
	set_source_tex();
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'info','ok',
		  __("The source file has been copied to project directory.")." ".sprintf(__"You can now edit it with button \"%s\" or with any editor.",__"Edit source file"));
	$dialog->run;
	$dialog->destroy;
    } else {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',
		  __"Error copying source file: %s",$!);
	$dialog->run;
	$dialog->destroy;
    }
}

sub edit_src {
    my $f=absolu($projet{'options'}->{'texsrc'});

    # create new one if necessary

    if(!-f $f) {
      debug "Creating new empty source file...";
      ("AMC::Filter::register::".$projet{'options'}->{'filter'})
	->default_content($f);
    }

    #

    debug "Editing $f...";
    my $editor=$o{'txt_editor'};
    if($projet{'options'}->{'filter'}) {
      my $type=("AMC::Filter::register::".$projet{'options'}->{'filter'})
	->filetype();
      $editor=$o{$type.'_editor'} if($o{$type.'_editor'});
    }
    commande_parallele($editor,$f);
}

sub valide_projet {
    set_source_tex();

    $projet{'_data'}=AMC::Data->new(absolu($projet{'options'}->{'data'}),
				    'progress'=>\%w);
    for (qw/layout capture scoring association report/) {
      $projet{'_'.$_}=$projet{'_data'}->module($_);
    }

    detecte_mep();
    detecte_analyse('premier'=>1);

    debug "Correction options : MB".$projet{'options'}->{'maj_bareme'};
    $w{'maj_bareme'}->set_active($projet{'options'}->{'maj_bareme'});

    transmet_pref($gui,'notation',$projet{'options'});

    $w{'main_window'}->set_title($projet{'nom'}.' - '.
				 'Auto Multiple Choice');

    noter_resultat();

    valide_liste('noinfo'=>1,'nomodif'=>1);

    transmet_pref($gui,'export',$projet{'options'});
    transmet_pref($gui,'pref_prep',$projet{'options'});
}

sub projet_ouvre {
    my ($proj,$deja)=(@_);

    my $new_source=0;

    # ouverture du projet $proj. Si $deja==1, alors il faut le creer

    if($proj) {
	my ($ok,$texsrc);

	# choix fichier latex si nouveau projet...
	if($deja) {
	    ($ok,$texsrc)=source_latex_choisir('nom'=>$proj);
	    if(!$ok) {
		return(0);
	    }
	    if($ok==1) {
		$new_source=1;
	    } elsif($ok==2) {
		$deja='';
	    }
	}

	quitte_projet();
	$projet{'nom'}=$proj;
	$projet{'options'}->{'texsrc'}=$texsrc;

	if(!$deja) {

	    if(-f fich_options($proj)) {
		debug "Reading options for project $proj...";

		$projet{'options'}={pref_xx_lit(fich_options($proj))};

		# pour effacer des trucs en trop venant d'un bug anterieur...
		for(keys %{$projet{'options'}}) {
		    delete($projet{'options'}->{$_})
			if($_ !~ /^ext_/ && !exists($projet_defaut{$_}));
		}

		# Old style CSV ticked option
		if($projet{'cochees'} && !$projet{'ticked'}) {
		  $projet{'ticked'}='01';
		  delete($projet{'cochees'});
		}

		debug "Read options:",
		  Dumper(\%projet);
	    } else {
		debug "No options file...";
	    }
	}

	$projet{'nom'}=$proj;

	# creation du repertoire et des sous-repertoires de projet

	for my $sous ('',qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf cr/zooms cr/diagnostic data scans exports:) {
	    my $rep=$o{'rep_projets'}."/$proj/$sous";
	    if(! -x $rep) {
		debug "Creating directory $rep...";
		mkdir($rep);
	    }
	}

	# recuperation des options par defaut si elles ne sont pas encore definies dans la conf du projet

	for my $k (keys %projet_defaut) {
	    if(! exists($projet{'options'}->{$k})) {
		if($o{'defaut_'.$k}) {
		    $projet{'options'}->{$k}=$o{'defaut_'.$k};
		    debug "New parameter (default) : $k";
		} else {
		    $projet{'options'}->{$k}=$projet_defaut{$k};
		    debug "New parameter : $k";
		}
	    }
	}

	$w{'onglets_projet'}->set_sensitive(1);

	valide_projet();

	$projet{'options'}->{'_modifie'}='';

	set_source_tex(1) if($new_source);

	return(1);
    }
}

sub quitte_projet {
    if($projet{'nom'}) {

      maj_export();
	valide_options_notation();

	my ($m,$mo)=sub_modif($projet{'options'});

	if($m || $mo) {
	    my $save=1;
	    if($m) {
		my $dialog = Gtk2::MessageDialog
		    ->new_with_markup($w{'main_window'},
				      'destroy-with-parent',
				      'question','yes-no',
				      sprintf(__"You did not save project <i>%s</i> options, which have been modified: do you want to save them before leaving?",$projet{'nom'}));
		my $reponse=$dialog->run;
		$dialog->destroy;

		if($reponse ne 'yes') {
		    $save='';
		}
	    }
	    projet_sauve() if($save);
	}

	%projet=();
    }
}

sub quitter {
    quitte_projet();

    if($o{'conserve_taille'}) {
	my ($x,$y)=$w{'main_window'}->get_size();
	if(!$o{'taille_x_main'} || !$o{'taille_y_main'}
	   || $x != $o{'taille_x_main'} || $y != $o{'taille_y_main'}) {
	    $o{'taille_x_main'}=$x;
	    $o{'taille_y_main'}=$y;
	    $o{'_modifie_ok'}=1;
	}
    }

    my ($m,$mo)=sub_modif(\%o);

    if($m || $mo) {
      my $save=1;
      if($m) {
	my $dialog = Gtk2::MessageDialog
	  ->new_with_markup($w{'main_window'},
			    'destroy-with-parent',
			    'question','yes-no',
			    __"You did not save main options, which have been modified: do you want to save them before leaving?");
	my $reponse=$dialog->run;
	$dialog->destroy;
	$save=0 if($reponse ne 'yes');
      }

      if($save) {
	sauve_pref_generales();
      }
    }

    Gtk2->main_quit;
}

sub bug_report {
    my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'info','ok',
			  __("In order to send a useful bug report, please attach the following documents:")."\n"
			  ."- ".__("an archive (in some compressed format, like ZIP, 7Z, TGZ...) containing the <b>project directory</b>, <b>scan files</b> and <b>configuration directory</b> (.AMC.d in home directory), so as to reproduce and analyse this problem.")."\n"
			  ."- ".__("the <b>log file</b> produced when the debugging mode (in Help menu) is checked. Please try to reproduce the bug with this mode activated.")."\n\n"
			  .sprintf(__("Bug reports can be filled at %s or sent to the address below."),
				   "<i>".__("AMC community site")."</i>",
				   )
	);
    my $ma=$dialog->get('message-area');
    my $web=Gtk2::LinkButton->new_with_label("http://project.auto-multiple-choice.net/projects/auto-multiple-choice/issues",__("AMC community site"));
    $ma->add($web);
    my $mail=Gtk2::LinkButton->new_with_label('mailto:paamc@passoire.fr',
					      'paamc@passoire.fr');
    $ma->add($mail);
    $ma->show_all();

    $dialog->run;
    $dialog->destroy;
}

#######################################

sub pref_change_delivery {
  my %oo=('email_transport'=>'');
  reprend_pref('pref',\%oo);
  for my $k (qw/sendmail SMTP/) {
    $w{'email_group_'.$k}->set_sensitive($k eq $oo{'email_transport'});
  }
}

my $email_sl;
my $email_key;
my $email_r;

sub send_emails {

  # are there some annotated answer sheets to send?

  $projet{'_report'}->begin_read_transaction('emNU');
  my $n=$projet{'_report'}->type_count(REPORT_ANNOTATED_PDF);
  my $n_annotated=$projet{'_capture'}->annotated_count();
  $projet{'_report'}->end_transaction('emNU');

  if($n==0) {
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'error','ok',
			__("There are no annotated corrected answer sheets to send.")
			." "
			.($n_annotated>0 ?
			  __("Please group the annotated sheets to PDF files to be able to send them.") :
			  __("Please annotate answer sheets and group them to PDF files to be able to send them.") )
		       );
    $dialog->run;
    $dialog->destroy;

    return();
  }

  # check perl modules availibility

  my @needs_module=(qw/Email::Address Email::MIME
		       Email::Sender Email::Sender::Simple/);
  if($o{'email_transport'} eq 'sendmail') {
    push @needs_module,'Email::Sender::Transport::Sendmail';
  } elsif($o{'email_transport'} eq 'SMTP') {
    push @needs_module,'Email::Sender::Transport::SMTP';
  }
  my @manque=();
  for my $m (@needs_module) {
    if(!check_install(module=>$m)) {
      push @manque,$m;
    }
  }
  if(@manque) {
    debug 'Mailing: Needs perl modules '.join(', ',@manque);

    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'error','ok',
			sprintf(__("Sending emails requires some perl modules that are not installed: %s. Please install these modules and try again."),
			'<b>'.join(', ',@manque).'</b>')
		       );
    $dialog->run;
    $dialog->destroy;

    return();
  }

  load Email::Address;

  # then check a correct sender address has been set

  my @sa=Email::Address->parse($o{'email_sender'});

  if(!@sa) {
    my $message;
    if($o{'email_sender'}) {
      $message.=sprintf(__("The email address you entered (%s) is not correct."),
			$o{'email_sender'}).
	"\n".__"Please edit your preferencies to correct your email address.";
    } else {
      $message.=__("You did not enter your email address.").
	"\n".__"Please edit the preferencies to set your email address.";
    }
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'error','ok',$message);
    $dialog->run;
    $dialog->destroy;

    return();
  }

  # Now check (if applicable) that sendmail path is ok

  if($o{'email_transport'} eq 'sendmail'
     && $o{'email_sendmail_path'}
     && !-f $o{'email_sendmail_path'}) {
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
# TRANSLATORS: Do not translate the 'sendmail' word.
			'error','ok',sprintf(__("The <i>sendmail</i> program cannot be found at the location you specified in the preferencies (%s). Please update your configuration."),$o{'email_sendmail_path'}));
    $dialog->run;
    $dialog->destroy;

    return();
  }

  #

  my $fl=absolu($projet{'options'}->{'listeetudiants'});
  $email_sl=AMC::NamesFile::new($fl,
				'encodage'=>bon_encodage('liste'),
				'identifiant'=>csv_build_name(),
			       );
  my ($err,$errlig)=$email_sl->errors();

  # find columns with emails in the students list file

  my %cols_email=$email_sl
    ->heads_count(sub { my @a=Email::Address->parse(@_);return(@a) });
  my @cols=grep { $cols_email{$_}>0 } (keys %cols_email);
  $cb_stores{'email_col'}=
    cb_model(map { $_=>$_ } (@cols));

  if(!@cols) {
    my $dialog = Gtk2::MessageDialog
      ->new_with_markup($w{'main_window'},
			'destroy-with-parent',
			'error','ok',
		       __"No email addresses has been found in the students list file. You need to write the students addresses in a column of this file.");
    $dialog->run;
    $dialog->destroy;

    return();
  }

  # which is the best column ?

  my $nmax=0;
  my $col_max='';

  for(@cols) {
    if($cols_email{$_}>$nmax) {
      $nmax=$cols_email{$_};
      $col_max=$_;
    }
  }

  $projet{'options'}->{'email_col'}=$col_max
    if(!$projet{'options'}->{'email_col'});

  # Then, open configuration window...
  my $gap=read_glade('mailing',
		     qw/emails_list email_dialog/);


  $w{'emails_list'}->set_model($emails_store);
  $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of a column containing copy numbers in a table showing all annotated answer sheets, when sending them to the students by email.
  $column = Gtk2::TreeViewColumn->new_with_attributes (__"copy",
						       $renderer,
						       text=> EMAILS_SC);
  $w{'emails_list'}->append_column ($column);
  $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of a column containing students names in a table showing all annotated answer sheets, when sending them to the students by email.
  $column = Gtk2::TreeViewColumn->new_with_attributes (__"name",
						       $renderer,
						       text=> EMAILS_NAME);
  $w{'emails_list'}->append_column ($column);
  $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of a column containing students email addresses in a table showing all annotated answer sheets, when sending them to the students by email.
  $column = Gtk2::TreeViewColumn->new_with_attributes (__"email",
						       $renderer,
						       text=> EMAILS_EMAIL);
  $w{'emails_list'}->append_column ($column);

  $projet{'_report'}->begin_read_transaction('emCC');
  $email_key=$projet{'_association'}->variable('key_in_list');
  $email_r=$projet{'_report'}->get_associated_type(REPORT_ANNOTATED_PDF);

  $emails_store->clear;
  for my $i (@$email_r) {
    my ($s)=$email_sl->data($email_key,$i->{'id'});
    $emails_store->set($emails_store->append,
		       EMAILS_ID,$i->{'id'},
		       EMAILS_EMAIL,'',
		       EMAILS_NAME,$s->{'_ID_'},
		       EMAILS_SC,pageids_string($projet{'_association'}->real_back($i->{'id'})),
		       );
  }

  $projet{'_report'}->end_transaction('emCC');

  $w{'emails_list'}->get_selection->set_mode(GTK_SELECTION_MULTIPLE);
  $w{'emails_list'}->get_selection->select_all;

  if($o{'conserve_taille'}) {
    if($o{'mailing_window_size'} &&
       $o{'mailing_window_size'} =~ /^([0-9]+)x([0-9]+)$/) {
      $w{'email_dialog'}->resize($1,$2);
    }
  }

  transmet_pref($gap,'email',$projet{'options'});
  my $resp=$w{'email_dialog'}->run;
  my @ids=();
  if($resp==1) {
    reprend_pref('email',$projet{'options'});
    # get selection
    my @selected=$w{'emails_list'}->get_selection->get_selected_rows;
    for my $i (@selected) {
      my $iter=$emails_store->get_iter($i);
      push @ids,$emails_store->get($iter,EMAILS_ID);
    }
  }
  if($o{'conserve_taille'}) {
    my $dims=join('x',$w{'email_dialog'}->get_size);
    if($dims ne $o{'mailing_window_size'}) {
      $o{'mailing_window_size'}=$dims;
      $o{'_modifie_ok'}=1;
    }
  }
  $w{'email_dialog'}->destroy;

  if($resp==1) {
    # writes the list of copies to send in a temporary file
    my $fh=File::Temp->new(TEMPLATE => "ids-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@ids)."\n";
    $fh->seek( 0, SEEK_END );

    commande('commande'=>["auto-multiple-choice","mailing",
			  pack_args("--project",absolu('%PROJET/'),
				    "--students-list",absolu($projet{'options'}->{'listeetudiants'}),
				    "--list-encoding",bon_encodage('liste'),
				    "--csv-build-name",csv_build_name(),
				    "--ids-file",$fh->filename,
				    "--email-column",$projet{'options'}->{'email_col'},
				    "--sender",$o{'email_sender'},
				    "--subject",$projet{'options'}->{'email_subject'},
				    "--text",$projet{'options'}->{'email_text'},
				    "--transport",$o{'email_transport'},
				    "--sendmail-path",$o{'email_sendmail_path'},
				    "--smtp-host",$o{'email_smtp_host'},
				    "--smtp-port",$o{'email_smtp_port'},
				    "--debug",debug_file(),
				    "--progression-id",'mailing',
				    "--progression",1,
				   ),
			 ],
	     'progres.id'=>'mailing',
	     'texte'=>__"Sending emails...",
	     'o'=>{'fh'=>$fh},
	     'fin'=>sub {
	       my $c=shift;
	       close($c->{'o'}->{'fh'});

	       my $ok=$c->variable('OK');
	       my $failed=$c->variable('FAILED');
	       my @message;
	       push @message,sprintf(__"%d message(s) has been sent.",$ok);
	       if($failed>0) {
		 push @message,"<b>".sprintf("%d message(s) could not be sent.",$failed)."</b>";
	       }
	       my $dialog = Gtk2::MessageDialog
		 ->new_with_markup($w{'main_window'},
				   'destroy-with-parent',
				   ($failed>0 ? 'warning' : 'info'),'ok',
				   join("\n",@message));
	       $dialog->run;
	       $dialog->destroy;
	     },
	    );
  }
}

sub email_change_col {
  my %oo=('email_col'=>'');
  reprend_pref('email',\%oo);

  my $i=$emails_store->get_iter_first;
  while(defined($i)) {
    my ($s)=$email_sl->data($email_key,$emails_store->get($i,EMAILS_ID));
    $emails_store->set($i,EMAILS_EMAIL,$s->{$oo{'email_col'}});
    $i=$emails_store->iter_next($i);
  }
}

#######################################

sub choose_columns {
  my ($type)=@_;

  my $l=$projet{'options'}->{'export_'.$type.'_columns'};

  my $fl=absolu($projet{'options'}->{'listeetudiants'});
  my $n=AMC::NamesFile::new($fl,
			    'encodage'=>bon_encodage('liste'),
			    'identifiant'=>csv_build_name(),
			   );

  my $i=1;
  my %selected=map { $_=>$i++ } (split(/,+/,$l));
  my %order=();
  @available=('student.copy','student.key','student.name',$n->heads());
  $i=0;
  for(@available) {
     if($selected{$_}) {
       $i=$selected{$_};
     } else {
       $i.='1';
     }
     $order{$_}=$i;
   }
  @available=sort { $order{$a} cmp $order{$b} } @available;

  my $gcol=read_glade('choose_columns',
		      qw/columns_list columns_instructions/);

  $col=$w{'choose_columns'}->style()->bg('prelight');
  for my $s (qw/normal insensitive/) {
    for my $k (qw/columns_instructions/) {
      $w{$k}->modify_base($s,$col);
    }
  }
  my $columns_store=Gtk2::ListStore->new('Glib::String','Glib::String');
  $w{'columns_list'}->set_model($columns_store);
  my $renderer=Gtk2::CellRendererText->new;
# TRANSLATORS: This is the title of a column containing all columns names from the students list file, when choosing which columns has to be exported to the spreadsheets.
  my $column = Gtk2::TreeViewColumn->new_with_attributes (__"column",
						       $renderer,
						       text=> 0);
  $w{'columns_list'}->append_column ($column);

  my @selected_iters=();
  for my $c (@available) {
    my $name=$c;
    $name=__("<full name>") if($c eq 'student.name');
    $name=__("<student identifier>") if($c eq 'student.key');
    $name=__("<student copy>") if($c eq 'student.copy');
    my $iter=$columns_store->append;
    $columns_store->set($iter,
			0,$name,
			1,$c);
    push @selected_iters,$iter if($selected{$c});
  }
  $w{'columns_list'}->set_reorderable(1);
  $w{'columns_list'}->get_selection->set_mode(GTK_SELECTION_MULTIPLE);
  for(@selected_iters) { $w{'columns_list'}->get_selection->select_iter($_); }

  my $resp=$w{'choose_columns'}->run;
  if($resp==1) {
    my @k=();
    my @s=$w{'columns_list'}->get_selection->get_selected_rows;
    for my $i (@s) {
      push @k,$columns_store->get($columns_store->get_iter($i),1);
    }
    $projet{'options'}->{'export_'.$type.'_columns'}=join(',',@k);
  }

  $w{'choose_columns'}->destroy;
}

sub choose_columns_current {
  choose_columns(lc($projet{'options'}->{'format_export'}));
}

#######################################

# PLUGINS

sub plugins_add {
  my $d=Gtk2::FileChooserDialog
    ->new(__("Install an AMC plugin"),
	  $w{'main_window'},'open',
	  'gtk-cancel'=>'cancel',
	  'gtk-ok'=>'ok');
  my $filter=Gtk2::FileFilter->new();
  $filter->set_name(__"Plugins (zip, tgz)");
  for my $ext (qw/ZIP zip TGZ tgz tar.gz TAR.GZ/) {
    $filter->add_pattern("*.$ext");
  }
  $d->add_filter($filter);

  my $r=$d->run;
  if($r eq 'ok') {
    my $plugin=$d->get_filename;
    $d->destroy;

    # unzip in a temporary directory

    my ($temp_dir,$error)=unzip_to_temp($plugin);

    if($error) {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',
			  sprintf(__("An error occured while trying to extract files from the plugin archive: %s."),$error));
      $dialog->run;
      $dialog->destroy;
      return();
    }

    # checks validity

    my ($nf,$main)=n_fich($temp_dir);
    if($nf<1) {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',
			  __"Nothing extracted from the plugin archive. Check it.");
      $dialog->run;
      $dialog->destroy;
      return();
    }
    if($nf>1 || !-d $main) {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',
			  __"This is not a valid plugin, as it contains more than one directory at the first level.");
      $dialog->run;
      $dialog->destroy;
      return();
    }

    if(!-d "$main/perl/AMC") {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',
			  __"This is not a valid plugin, as it does not contain a perl/AMC subdirectory.");
      $dialog->run;
      $dialog->destroy;
      return();
    }

    my $name=$main;
    $name =~ s/.*\///;

    # already installed?

    if($name=~/[^.]/ && -e "$o_dir/plugins/$name") {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'question','yes-no',
			  sprintf(__("A plugin is already installed with the same name (%s). Do you want to delete the old one and overwrite?"),
				  "<b>$name</b>"));
      my $r=$dialog->run;
      $dialog->destroy;
      return if($r ne 'yes');

      remove_tree("$o_dir/plugins/$name",{'verbose'=>0,'safe'=>1,'keep_root'=>0});
    }

    # go!

    debug "Installing plugin $name to $o_dir/plugins";

    if(system('mv',$main,"$o_dir/plugins")!=0) {
      my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'error','ok',
			  sprintf(__("Error while moving the plugin to the user plugin directory: %s"),$!));
      my $r=$dialog->run;
      $dialog->destroy;
      return();
    }

    my $dialog = Gtk2::MessageDialog
	->new_with_markup($w{'main_window'},
			  'destroy-with-parent',
			  'info','ok',
			  __"Please restart AMC before using the new plugin...");
      my $r=$dialog->run;
      $dialog->destroy;

  } else {
    $d->destroy;
  }
}

#######################################

sub cleanup_dialog {
  my %files;

  my $gap=read_glade('cleanup');

  my $dialog=$gap->get_object('cleanup');

  my $reponse=$dialog->run();

  for(qw/zooms annotated_pages/) {
    $files{$_}=$gap->get_object('component_'.$_)->get_active();
  }

  $dialog->destroy();

  debug "RESPONSE=$reponse";

  return() if($reponse!=10);

  my $n=0;

  if($files{'zooms'}) {
    debug "Removing zooms...";
    $n+=remove_tree(absolu('%PROJET/cr/zooms'),
		    {'verbose'=>0,'safe'=>1,'keep_root'=>1});
  }

  if($files{'annotated_pages'}) {
    debug "Removing annotated pages...";
    $n+=remove_tree(absolu('%PROJET/cr/corrections/jpg'),
		    {'verbose'=>0,'safe'=>1,'keep_root'=>1});
  }

  $dialog = Gtk2::MessageDialog
    ->new($w{'main_window'},
	  'destroy-with-parent',
	  'info','ok',
	  __("%s files were removed."),$n);
  $dialog->run;
  $dialog->destroy;
}

#######################################

if($o{'conserve_taille'} && $o{'taille_x_main'} && $o{'taille_y_main'}) {
    $w{'main_window'}->resize($o{'taille_x_main'},$o{'taille_y_main'});
}

projet_ouvre($ARGV[0]);

#######################################
# For MacPorts with latexfree variant, for example

if("0" =~ /(1|true|yes)/i) {
    my $message='';
    if(!commande_accessible("kpsewhich")) {
	$message=sprintf(__("I don't find the command %s."),"kpsewhich")
	    .__("Perhaps LaTeX is not installed?");
    } else {
	if(!get_sty()) {
# TRANSLATORS: Do not translate 'auto-multiple-choice latex-link', which is a command to be typed on MacOsX
	    $message=__("The style file automultiplechoice.sty seems to be unreachable. Try to use command 'auto-multiple-choice latex-link' as root to fix this.");
	}
    }
    if($message) {
	my $dialog = Gtk2::MessageDialog
	    ->new($w{'main_window'},
		  'destroy-with-parent',
		  'error','ok',$message);
	$dialog->run;
	$dialog->destroy;
    }
}

#######################################

test_commandes();

Gtk2->main();

1;

__END__

