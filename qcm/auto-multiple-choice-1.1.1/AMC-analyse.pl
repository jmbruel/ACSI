#! /usr/bin/perl
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

use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Getopt::Long;

use AMC::Basic;
use AMC::Exec;
use AMC::Queue;
use AMC::Calage;
use AMC::Image;
use AMC::Boite qw/min max/;
use AMC::Data;
use AMC::DataModule::capture qw/:zone :position/;
use AMC::DataModule::layout qw/:flags/;
use AMC::Gui::Avancement;

my $pid='';
my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-analyse : signal $signame, transfered to $pid...";
    kill 2,$pid if($pid);
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $data_dir="";
my $cr_dir="";
my $debug='';
my $debug_image_dir='';
my $debug_image='';
my $progress=0;
my $progress_id=0;
my $scans_list;
my $n_procs=0;
my $project_dir='';
my $tol_mark='';
my $prop=0.8;
my $bw_threshold=0.6;
my $blur='1x1';
my $threshold='60%';
my $multiple='';
my $ignore_red=1;
my $pre_allocate=0;

GetOptions("data=s"=>\$data_dir,
	   "cr=s"=>\$cr_dir,
	   "tol-marque=s"=>\$tol_mark,
	   "prop=s"=>\$prop,
	   "bw-threshold=s"=>\$bw_threshold,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "liste-fichiers=s"=>\$scans_list,
	   "projet=s"=>\$project_dir,
	   "n-procs=s"=>\$n_procs,
	   "debug-image-dir=s"=>\$debug_image_dir,
	   "multiple!"=>\$multiple,
	   "ignore-red!"=>\$ignore_red,
	   "pre-allocate=s"=>\$pre_allocate,
	   );

use_gettext;

set_debug($debug);

$queue=AMC::Queue::new('max.procs',$n_procs);

my $progress_h=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data;
my $layout;

# Reads scan files from command line

my @scans=@ARGV;

# Adds scan files from a list file

if($scans_list && open(LISTE,$scans_list)) {
    while(<LISTE>) {
	chomp;
	if(-f $_) {
	    debug "Scan from list : $_";
	    push @scans,$_;
	} else {
	    debug_and_stderr "WARNING. File does not exist : $_";
	}
    }
    close(LISTE);
}

exit(0) if($#scans <0);

sub error {
    my ($e,$silent)=shift;
    if($debug_image &&
       $process->mode() eq 'opencv') {
	$process->commande("output ".$debug_image);
	$process->ferme_commande;
    }
    if($silent) {
	debug $e;
    } else {
	debug "ERROR($scan): $e\n";
	print "ERROR($scan): $e\n";
    }
    exit(1);
}

sub check_rep {
    my ($r,$create)=(@_);
    if($create && $r && ! -x $r) {
	mkdir($r);
    }

    die "ERROR: directory does not exist: $r" if(! -d $r);
}

$data_dir=$project_dir."/data" if($project_dir && !$data_dir);
$cr_dir=$project_dir."/cr" if($project_dir && !$cr_dir);

check_rep($data_dir);
check_rep($cr_dir,1);

my $delta=$progress/(1+$#scans);

my $tol_mark_plus=1/5;
my $tol_mark_moins=1/5;

if($tol_mark) {
    if($tol_mark =~ /(.*),(.*)/) {
	$tol_mark_moins=$1;
	$tol_mark_plus=$2;
    } else {
	$tol_mark_moins=$tol_mark;
	$tol_mark_plus=$tol_mark;
    }
}

########################################
# Gets layout data from a (random) page

sub code_cb {
    my ($nombre,$chiffre)=(@_);
    return("$nombre:$chiffre");
}

sub detecte_cb {
    my $k=shift;
    if($k =~ /^([0-9]+):([0-9]+)$/) {
	return($1,$2);
    } else {
	return();
    }
}

sub get_layout_data {
  my ($student,$page,$all)=@_;
  my $r={'corners.test'=>{},'zoom.file'=>{},'darkness.data'=>{},
	'boxes'=>{},'flags'=>{}};

  ($r->{'width'},$r->{'height'},$r->{'markdiameter'})
    =$layout->dims($student,$page);
  $r->{'frame'}=AMC::Boite::new_complete($layout->all_marks($student,$page));

  my $sth=$layout->statement('digitInfo');
  $sth->execute($student,$page);
  while(my $c=$sth->fetchrow_hashref) {
    my $k=code_cb($c->{'numberid'},$c->{'digitid'});
    $r->{'boxes'}->{$k}=AMC::Boite::new_MN(map { $c->{$_} }
					   (qw/xmin ymin xmax ymax/));
  }

  if($all) {
    $sth=$layout->statement('boxInfo');
    $sth->execute($student,$page);
    while($c=$sth->fetchrow_hashref) {
      $r->{'boxes'}->{$c->{'question'}.".".$c->{'answer'}}=
	AMC::Boite::new_MN(map { $c->{$_} }
			   (qw/xmin ymin xmax ymax/));
      $r->{'flags'}->{$c->{'question'}.".".$c->{'answer'}}=
	$c->{'flags'};
    }
    $sth=$layout->statement('namefieldInfo');
    $sth->execute($student,$page);
    while($c=$sth->fetchrow_hashref) {
      $r->{'boxes'}->{'namefield'}=
	AMC::Boite::new_MN(map { $c->{$_} }
			   (qw/xmin ymin xmax ymax/));
    }
  }

  return($r);
}

my $t_type='lineaire';
my $cale=AMC::Calage::new('type'=>$t_type);

$data=AMC::Data->new($data_dir);
$layout=$data->module('layout');

$layout->begin_read_transaction('cRLY');

if($layout->pages_count()==0) {
  $layout->end_transaction('cRLY');
  error("No layout");
}
debug "".$layout->pages_count()." layouts\n";

my @ran=$layout->random_studentPage;
my $random_layout=get_layout_data(@ran);

$layout->end_transaction('cRLY');

$data->disconnect;

########################################
# Fits marks on scan to layout data

sub command_transf {
  my ($process,$cale,@args)=@_;

  my @r=$process->commande(@args);
  for(@r) {
    $cale->{'t_'.$1}=$2 if(/([a-f])=(-?[0-9.]+)/);
    $cale->{'MSE'}=$1 if(/MSE=([0-9.]+)/);
  }
}

sub marks_fit {
  my ($process,$ld,$scan_frame)=@_;
  if($process->mode() eq 'opencv') {

    $cale=AMC::Calage::new('type'=>'lineaire');
    command_transf($process,$cale,
		   join(' ',"optim",
			$ld->{'frame'}->draw_points()));

  } else {

    my @cx=map { $ld->{'frame'}->coordonnees($_,'x') } (0..3);
    my @cy=map { $ld->{'frame'}->coordonnees($_,'y') } (0..3);
    my @cxp=map { $scan_frame->coordonnees($_,'x') } (0..3);
    my @cyp=map { $scan_frame->coordonnees($_,'y') } (0..3);

    $cale->calage(\@cx,\@cy,\@cxp,\@cyp);

  }

  debug "MSE=".$cale->mse();

  $ld->{'transf'}=$cale;
}

##################################################
# Reads darkness of a particular box

sub measure_box {
    my ($process,$ld,$k,@spc)=(@_);
    my $r=0;

    $ld->{'corners.test'}->{$k}=AMC::Boite::new();

    if($process->mode() eq 'opencv' && @spc) {
	if($k =~ /^([0-9]+)\.([0-9]+)$/) {
	    $process->commande(join(' ',"id",@spc[0,1],$1,$2))
	}
    }

    $ld->{'boxes.scan'}->{$k}=$ld->{'boxes'}->{$k}->clone;
    $ld->{'boxes.scan'}->{$k}->transforme($ld->{'transf'});

    if(!($ld->{'flags'}->{$k} & BOX_FLAGS_DONTSCAN)) {
      for($process->commande($ld->{'boxes.scan'}->{$k}
			     ->commande_mesure($prop))) {

	if(/^COIN\s+(-?[0-9\.]+),(-?[0-9\.]+)$/) {
	  $ld->{'corners.test'}->{$k}->def_point_suivant($1,$2);
	}
	if(/^PIX\s+([0-9]+)\s+([0-9]+)$/) {
	  $r=($2==0 ? 0 : $1/$2);
	  debug sprintf("Binary box $k: %d/%d = %.4f\n",$1,$2,$r);
	  $ld->{'darkness.data'}->{$k}=[$2,$1];
	}
	if(/^ZOOM\s+(.*)/) {
	  $ld->{'zoom.file'}->{$k}=$1;
	}
      }
    }

    return($r);
}

########################################
# Reads ID (student/page/check) from binary boxes

sub decimal {
    my @ch=(@_);
    my $r=0;
    for (@ch) {
	$r=2*$r+$_;
    }
    return($r);
}

sub get_binary_number {
  my ($process,$ld,$i)=@_;

  my @ch=();
  my $a=1;
  my $fin='';
  do {
    my $k=code_cb($i,$a);
    if($ld->{'boxes'}->{$k}) {
      push @ch,(measure_box($process,$ld,$k)>.5 ? 1 : 0);
      $a++;
    } else {
      $fin=1;
    }
  } while(!$fin);
  return(decimal(@ch));
}

sub get_id_from_boxes {
  my ($process,$ld)=@_;

  @epc=map { get_binary_number($process,$ld,$_) } (1,2,3);
  my $id_page="+".join('/',@epc)."+";
  print "Page : $id_page\n";
  debug("Found binary ID: $id_page");
  return(@epc);
}

my $process;
my $temp_loc;
my $temp_dir;
my $commands;

sub one_scan {
  my ($scan,$allocate)=@_;
  my $sf=$scan;
  if($project_dir) {
    $sf=abs2proj({'%PROJET',$project_dir,
		  '%HOME'=>$ENV{'HOME'},
		  ''=>'%PROJET',
		 },
		 $sf);
  }

  my $sf_file=$sf;
  $sf_file=~ s:.*/::;
  $debug_image=$debug_image_dir."/$sf_file.png" if($debug_image_dir);

  debug "Analysing scan $scan";

  $data->connect;
  $layout=$data->module('layout');

  $commands=AMC::Exec::new('AMC-analyse');
  $commands->signalise();

  $process=AMC::Image::new('');

  debug "Mode: ".$process->mode();

  ##########################################
  # Converts the scan to PPM if necessary
  ##########################################

  if($process->mode() eq 'opencv') {
    # Using OpenCV: current image types are OK, don't convert to PPM.
    $ppm=$scan;
  } else{
    # Using custom (slow) image processing command: needs PPM for input
    # 1) converting to PPM

    if($blur || $threshold || $scan !~ /\.ppm$/) {
	print "Converting to ppm...\n";

	$temp_loc=tmpdir();
	$temp_dir = tempdir( DIR=>$temp_loc,
			     CLEANUP => (!get_debug()) );
	debug "dir = $temp_dir";
	$ppm="$temp_dir/image.ppm";


	my @ca=(magick_module('convert'));
	push @ca,"-blur",$blur if($blur);
	push @ca,"-threshold",$threshold if($threshold);
	push @ca,$scan,$ppm;
	$commands->execute(@ca);
    } else {
	$ppm=$scan;
    }

    # 2) Reading image size

    open(CMD,"identify $ppm|");
    while(<CMD>) {
	if(/\sP[NBP]M\s+([0-9]+)x([0-9]+)/) {
	    $tiff_x=$1;
	    $tiff_y=$2;
	}
    }
    close(CMD);

    error("Unknown size") if(!$tiff_x);

    debug "IMAGE = $scan ($tiff_x x $tiff_y)\n";
  }

  $process->set('fichier',$ppm);

  ##########################################
  # Marks detection
  ##########################################

  if($process->mode() eq 'opencv') {

    my @r;
    my @args=('-x',$random_layout->{'width'},
	      '-y',$random_layout->{'height'},
	      '-d',$random_layout->{'markdiameter'},
	      '-p',$tol_mark_plus,'-m',$tol_mark_moins,
	      '-t',$bw_threshold,
	      '-o',($debug_image ? $debug_image : 1)
	);

    push @args,'-P' if($debug_image);
    push @args,'-r' if($ignore_red);

    $process->set('args',\@args);

    @r=$process->commande("load ".$ppm);
    my @c=();
    for(@r) {
	if(/Frame\[([0-9]+)\]:\s*(-?[0-9.]+)\s*[,;]\s*(-?[0-9.]+)/) {
	    push @c,$2,$3;
	}
    }
    $cadre_general=AMC::Boite::new_complete(@c);

  } else {

    $rx=$tiff_x / $width;
    $ry=$tiff_y / $height;

    $taille=$markdiameter*($rx+$ry)/2;
    $taille_max=$taille*(1+$tol_mark_plus);
    $taille_min=$taille*(1-$tol_mark_moins);

    debug "rx = $rx   ry = $ry\n";
    debug(sprintf("Target sign size : %.2f (%.2f to %.2f)",
		  $taille,
		  $taille_min,$taille_max));

    my $lisse_trous=1+int(($taille_min+$taille_max)/2 /20);
    my $lisse_pouss=1+int(($taille_min+$taille_max)/2 /8);

    print "Morphological operations (+$lisse_trous-$lisse_pouss) and signs detection...\n";

    $process->commande("etend $lisse_trous");
    $process->commande("erode ".($lisse_trous+$lisse_pouss));
    $process->commande("etend $lisse_pouss");
    $process->commande("calccc");

    for($process->commande("magick")) {
	if(/\(([0-9]+),([0-9]+)\)-[^\s]*\s+:\s+([0-9]+)\s*x\s*([0-9]+)/) {
	    push @box,AMC::Boite::new_MD($1,$2,$3,$4);
	}
    }

    $process->ferme_commande();

    print "".($#box+1)." boxes.\n";

    debug join("\n",map { $_->txt(); } @box);

    print "Searching signs...\n";

    @okbox=grep { $_->bonne_etendue($taille_min,$taille_max) } @box;

    if($#okbox < 3) {
	error("Only ".(1+$#okbox)." signs detected / needs at least 4");
    }

    @okbox=AMC::Boite::extremes(@okbox);

    if(get_debug()) {
	for my $c (@okbox) {
	    my ($dx,$dy)=$c->etendue_xy();
	    debug(sprintf("Sign size: $dx x $dy (%6.2f | %6.2f %%)",
			  100*($dx-$taille)/$taille,100*($dy-$taille)/$taille));
	}
    }

    $cadre_general=AMC::Boite::new_complete(map { $_->centre() } (@okbox));
  }

  debug "Global frame:",
    $cadre_general->txt();

  ##########################################
  # ID detection
  ##########################################

  my @epc;
  my $upside_down=0;
  my $ok;

  marks_fit($process,$random_layout,$cadre_general);
  @epc=get_id_from_boxes($process,$random_layout);

  $layout->begin_read_transaction('cFLY');
  $ok=$layout->exists(@epc);
  $layout->end_transaction('cFLY');

  if($process->mode() eq 'opencv' && !$ok) {
    # Unknown ID: tries again upside down
    $process->commande("rotate180");
    marks_fit($process,$random_layout);
    @epc=get_id_from_boxes($process,$random_layout);
    $upside_down=1;

    $layout->begin_read_transaction('cFLY');
    $ok=$layout->exists(@epc);
    $layout->end_transaction('cFLY');
  }

  if(!$ok) {
    # Failed!
    # Page ID has not been found: report it in the database.
    my $capture=AMC::Data->new($data_dir)->module('capture');
    $capture->begin_transaction('CFLD');
    $capture->failed($sf);
    $capture->end_transaction('CFLD');

    error(sprintf("No layout for ID +%d/%d/%d+",@epc)) ;
  }

  if($process->mode() eq 'opencv') {
    command_transf($process,$random_layout->{'transf'},"rotateOK");
  }

  ##########################################
  # Get all boxes positions from the right page
  ##########################################

  $layout->begin_read_transaction('cELY');
  my $ld=get_layout_data(@epc[0,1],1);
  $layout->end_transaction('cELY');

  # But keep all results from binary boxes analysis

  for my $cat (qw/boxes boxes.scan corners.test darkness.data zoom.file/) {
    for my $k (%{$random_layout->{$cat}}) {
      $ld->{$cat}->{$k}=$random_layout->{$cat}->{$k}
	if(! $ld->{$cat}->{$k});
    }
  }

  $ld->{'transf'}=$random_layout->{'transf'};

  ##########################################
  # Get a free copy number
  ##########################################

  my $capture=AMC::Data->new($data_dir)->module('capture');

  @spc=@epc[0,1];
  if(!$debug_image) {
    if($multiple) {
      $capture->begin_transaction('cFCN');
      push @spc,$capture->new_page_copy(@epc[0,1],$allocate);
      debug "WARNING: pre-allocation failed. $allocate -> "
	.pageids_string(@spc) if($pre_allocate && $allocate != $spc[2]);
      $capture->set_page_auto($sf,@spc,-1,
			      $ld->{'transf'}->params);
      $capture->end_transaction('cFCN');
    } else {
      push @spc,0;
    }
  }

  my $zoom_dir;
  my $zoom_subdir;

  if($cr_dir) {

    $zoom_subdir=pageids_string(@spc,'path'=>1);
    $zoom_dir="$cr_dir/zooms/".$zoom_subdir;

    # clear old analysis results files

    clear_old('analysis result',
	      $zoom_dir);

    if($process->mode() eq 'opencv') {
      $process->commande("zooms $zoom_dir");
    }
  }

  ##########################################
  # Read darkness data from all boxes
  ##########################################

  for my $k (keys %{$ld->{'boxes'}}) {
    measure_box($process,$ld,$k,@spc) if($k =~ /^[0-9]+\.[0-9]+$/);
  }

  if($out_cadre && ($process->mode() eq 'opencv')) {
    $process->commande("annote ".pageids_string(@spc));
  }

  error("End of diagnostic",1) if($debug_image);

  ##########################################
  # Creates layout image report
  ##########################################

  $layout_file="page-".pageids_string(@spc,'path'=>1).".jpg";
  $out_cadre="$cr_dir/$layout_file"
    if($cr_dir && !$out_cadre);

  if($out_cadre && ($process->mode() eq 'opencv')) {
    $process->commande("output ".$out_cadre);
  }

  ##########################################
  # Rotates scan if it is upside-down
  ##########################################

  if($upside_down) {
    # Rotates the scan file
    print "Rotating...\n";

    $commands->execute(magick_module("convert"),
			"-rotate","180",$scan,$scan);
  }

  ##########################################
  # Some more image reports
  ##########################################

  my $nom_file="name-".studentids_string(@spc[0,2]).".jpg";

  my $whole_page;

  if($out_cadre || $nom_file) {
    debug "Reading scan $scan for extractions...";
    $whole_page=magick_perl_module()->new();
    $whole_page->Read($scan);
  }

  # Name field sub-image

  if($nom_file && $ld->{'boxes'}->{'namefield'}) {
    my $n=$ld->{'boxes'}->{'namefield'}->clone;
    $n->transforme($ld->{'transf'});
    clear_old('name image file',"$cr_dir/$nom_file");

    debug "Name box : ".$n->txt();
    my $e=$whole_page->Clone();
    $e->Crop(geometry=>$n->etendue_xy('geometry',$zoom_plus));
    debug "Writing to $cr_dir/$nom_file...";
    $e->Write("$cr_dir/$nom_file");
  }

  # layout image report

  if($out_cadre && ($process->mode ne 'opencv')) {

    print "Annotating image...\n";
    debug "Annotating image...\n";

    # transcription de l'identifiant lu

    $whole_page->Annotate(text=>pageids_string(@spc),
			    geometry=>"+0+96",
			    pointsize=>96,
			    font=>"Courier",
			    fill=>"blue",stroke=>'blue');

    ###############################################
    # cases du modele $cale->transformees, avec annotation
    for my $k (keys %{$ld->{'corners.test'}}) {
	# case
	$whole_page->Draw(primitive=>'polygon',
			    fill=>'none',stroke=>'blue',strokewidth=>1,
			    points=>$ld->{'boxes.scan'}->{$k}->draw_points());

	# part de la case testee
	$whole_page->Draw(primitive=>'polygon',
			    fill=>'none',stroke=>'magenta',strokewidth=>1,
			    points=>$ld->{'corners.test'}->{$k}->draw_points());
      }

    ###############################################
    # trace des cadres

    $whole_page->Draw(primitive=>'polygon',
			fill=>'none',stroke=>'red',strokewidth=>1,
			points=>$cadre_general->draw_points());

    $cadre_origine->transforme($cale);
    $whole_page->Draw(primitive=>'polygon',
			fill=>'none',stroke=>'blue',strokewidth=>1,
			points=>$cadre_origine->draw_points());

    $whole_page->Write($out_cadre);

    debug "-> $out_cadre\n";
  }

  ##########################################
  # Writes results to the database
  ##########################################

  $capture->begin_transaction('CRSL');
  $capture->variable('annotate_source_change',time());

  $capture->set_page_auto($sf,@spc,time(),
			  $ld->{'transf'}->params);

  # removes (if exists) old entry in the failed database
  $capture->statement('deleteFailed')->execute($sf);

  $capture->set_layout_image(@spc,$layout_file);

  $cadre_general->to_data($capture,
			  $capture->get_zoneid(@spc,ZONE_FRAME,0,0,1),
			  POSITION_BOX);

  for my $k (keys %{$ld->{'boxes'}}) {
    my $zoneid;
    if($k =~ /^([0-9]+)\.([0-9]+)$/) {
      my $question=$1;
      my $answer=$2;
      $zoneid=$capture->get_zoneid(@spc,ZONE_BOX,$question,$answer,1);
      $ld->{'corners.test'}->{$k}->to_data($capture,$zoneid,POSITION_MEASURE)
	if($ld->{'corners.test'}->{$k});
    } elsif(($n,$i)=detecte_cb($k)) {
      $zoneid=$capture->get_zoneid(@spc,ZONE_DIGIT,$n,$i,1);
    } elsif($k eq 'namefield') {
      $zoneid=$capture->get_zoneid(@spc,ZONE_NAME,0,0,1);
      $capture->statement('setZoneAuto')
	->execute(-1,-1,$nom_file,$zoneid);
    }

    if($zoneid) {
      if($k ne 'namefield') {
	if($ld->{'flags'}->{$k} & BOX_FLAGS_DONTSCAN) {
	  debug "Box $k is DONT_SCAN";
	} elsif($ld->{'darkness.data'}->{$k}) {
	  $capture->statement('setZoneAuto')
	    ->execute(@{$ld->{'darkness.data'}->{$k}},
		      $zoom_subdir."/".$ld->{'zoom.file'}->{$k},$zoneid);
	} else {
	  debug "No darkness data for box $k";
	}
      }
      if($ld->{'boxes'}->{$k} && !$ld->{'boxes.scan'}->{$k}) {
	$ld->{'boxes.scan'}->{$k}=$ld->{'boxes'}->{$k}->clone;
	$ld->{'boxes.scan'}->{$k}->transforme($ld->{'transf'});
      }
      $ld->{'boxes.scan'}->{$k}
	->to_data($capture,$zoneid,POSITION_BOX);
    }
  }
  $capture->end_transaction('CRSL');

  $process->ferme_commande();

  $progress_h->progres($delta);
}

my $scan_i=0;

for my $s (@scans) {
  my $a=($pre_allocate ? $pre_allocate+$scan_i : 0);
  debug "Pre-allocate ID=$a for scan $s\n" if($pre_allocate);
  $queue->add_process(\&one_scan,$s,$a);
  $scan_i++;
}

$queue->run();

$progress_h->fin();
