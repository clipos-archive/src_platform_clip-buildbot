# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2016-2018 ANSSI. All Rights Reserved.
# Recupere un log complet des revisions
# Rend une hash dont les clefs sont les versions et les valeurs 
#des refs sur une liste de noms de paquets modifiés. 
use XML::LibXML;

sub get_packets 
{
  my %return;
  $output=shift;
  for ($output=~/(^-{72}.*?)(?=^-{72})/msg)
  { 
    my %hashatom;
    my $modified_file2pkgn = sub {
      $a=shift;
      if ($a=~/portage[^\/]*\/eclass\/(.*)/)
      {	
		#For eclasses we leave the .eclass suffix
		#Full set of depending packet cannot be determined yet
		#One has to examine what eclasses are really present at the
		#time of the revision in clip-int
		$hashatom{$1}=1;
      }
      elsif ($a=~/portage\S*?\/(\S*?\/\S*?)\/.*/)#\.ebuild/) 
      	{
	  $hashatom{$1}=1;
	} 
    };
#pour chaque commit
    my $rev;
    /(^r(\d+))/m;
    $rev=$1;
    next if($2<$currentrev);#Just keep meaningfull revisions
#    print "revision get_paclkets $rev";
#On commence par sortir les 3 premieres lignes 
    s/(.*?\n){3}//;
#on vire tout ce qui suit ticket endebut de ligne
    s/\s*^ticket.*//sm;
#ensuite on a des noms de fichiers 
    @filenames=(/^\s+[AM]\s+(.*)/mg);
#on extrait les atomes, on elimine les ligne correspondant a des distfiles etc
    map {&$modified_file2pkgn( $_)} @filenames;
    $,=" ";
    my @toto=(keys %hashatom);
    $return{$rev}=\@toto;
  }
  return \%return;
}


sub docompile
# do the actual compilation job
#
# Input : atoms or filename ending by .eclass
#	  (if an eclass is modified one has to inspect _at the exact revision_
#	    what are really the packet impacted, it can only be done in sdk-test) 
#
#

{
	my ($rev,$refpack)=@_;	
	my $diff; 
	my @specs;
	my $name;
	my $ssh;
	local $SIG{'INT'} = sub
	{
	  system("/usr/share/clip-buildbot/bin/wrapper-lxc-test-stop $name") if($name);               
	  print 'BYE!'; 
	  exit(0);;
	};
#First we launch an administrative container
#Just here for computing the set of packets to compile
	{my $ssh=start_sdk_test_ssh($name);#$name is set by this sub

	$diff=$ssh->capture("cd $ENV{'CLIP-SDK-CLIP-INT'}; svn up -$rev\n");
	print "do compile revision $rev";

	for $i (@{$refpack})
	      {
		my $out,$err;
		if ($i=~/\.eclass$/m)
		{
#It's an eclass .... let's see who has to be recompiled
		   push @{refpack},eclass2pckgn($ssh,$i)
		}
		else
		{
#it an atom one have to find which specie it belongs to (multiple hit possible)
#and clip-compile the right way
		  push @specs,map {s:.*/specs/(.*?/.*?)\.spec.*:\1:r} specs_having($ssh,$i);
		}
	      }
#stop the administrative container 
	}#$ssh->close();
	system("/usr/share/clip-buildbot/bin/wrapper-lxc-test-stop $name");
	
#do the compilation job for each specie 
#refresh sdk between each spec
	for $sp (@specs)
	{
	     {
	      my $ssh=start_sdk_test_ssh($name);#$name is set by this sub
	      $diff=$ssh->capture("cd $ENV{'CLIP-SDK-CLIP-INT'}; svn up -$rev\n");
	      print "compiling for $sp";
       	      for $i (@{$refpack})
     	        {
		  print "Compiling $i";
		  compile_pkg_spec($rev,$i,$sp,$ssh);
		}
	     }#$ssh->close(); 
	     system("/usr/share/clip-buildbot/bin/wrapper-lxc-test-stop $name");

	}
	continue
	{
	  print "\n\n";
	}
}

sub compile_pkg_spec
{
  my ($rev,$i,$sp,$ssh)=@_;
  my $error=0;
  my $out,$in,$fic;
  print $i;
  make_path("$ENV{'CLIP-BUILDBOT-LOG-DIR'}/log/$rev/$sp/".dirname($i));;
  open($fic, ">", "$ENV{'CLIP-BUILDBOT-LOG-DIR'}/log/${rev}/$sp/".$i.".log") ;

#Incoherent bug /etc/portage not found otherwise
  ($out,$err)=$ssh->capture2("mv /etc/portage /etc/potage ");
  ($out,$err)=$ssh->capture2("mv /etc/potage /etc/portage ");
#end bug

  print "clip-compile $sp --depends -pkgn $i";
  $out=$ssh->capture("clip-compile $sp --depends -pkgn $i 2>&1");
  $error=$ssh->error;
  print $fic "Dependency !\n";
  print $fic $out;

  print "clip-compile $sp -pkgn $i";
  $out=$ssh->capture("clip-compile $sp -pkgn $i 2>&1");
  $error|=$ssh->error;
  print $fic "Compilation !\n";
  print $fic $out;
  close $fic;
  if($error)
  {
    print "ERROR!!!!!";
    make_path("$ENV{'CLIP-BUILDBOT-LOG-DIR'}/error/$rev/$sp/".dirname($i));;
    system("ln -s $ENV{'CLIP-BUILDBOT-LOG-DIR'}/log/$rev/$sp/${i}.log "
    		."$ENV{'CLIP-BUILDBOT-LOG-DIR'}/error/$rev/$sp/${i}.log");
#
#HERE Send mail
#
    $commiter_email=`svnlook author -$rev $ENV{'CLIP-MIRROR-PATH'}`;
#sendmail_to_commiter($commiter_email);
  }
  else
  {
#Everything compiled cleanly extract the .deb from 
#the ephemeral containers and copy them to the mirror 
#container
#     in which directory have we put le .deb files?
      my $rep=($sp=~s/.*\/(.*)/\1/r);

      for my $fic ($ssh->capture("ls /home/lambda/build/debs/$rep/"))
      {
#remove older versions prior to copy  
	chomp $fic;
	my $stemfile=$fic=~s/_.*//r;
	my $poub;
	my $locpath="$ENV{'CLIP-BUILDBOT-MIRROR-LXC'}/rootfs//home/lambda/build/debs/$rep/";
#cleanup previous files 
#	system "rm $poub" while($poub=glob("$locpath/$stemfile*"));
#
# TODO: discuss Mickael if it is a good idea

#now copy files from test to mirror sdk
	$ssh->scp_get("/home/lambda/build/debs/$rep/$fic","$ENV{'CLIP-BUILDBOT-MIRROR-LXC'}/rootfs//home/lambda/build/debs/$rep");
      }
    if ($i=~/^clip-conf/)
    {
      #check if pckdb is coherent and if .conf files are up to date	
      check_coherency($rev,$i,$ssh);
      #self explanatory
      update_mirror($ssh,$i);
    } 
  }

}

sub merge_unique
{
  my ($refa,$refb)=@_;
  my %tmphash;
  my @tmp;
  $tmphash{$_}=1 for @{$refa};
  $tmphash{$_}=1 for @{$refb};
  @tmp=(keys %tmphash);
 print "ici ,", @tmp;
  $_[0]=\@tmp;
}

sub eclass_graph
{
#
#  Ok the resolution algorihtm as I understand :
#   -in the portage directory where the ebuild is located find a directory named
#               eclass
#   -find the direct eclass
#   -for the inherited eclass just look here 
#
#
 
  my ($ssh,$eclass)=@_;
  $ssh->capture("pushd");
# in which directory is located the eclass ?
  my $dir=dirname($eclass);

  #first find all the eclasses
  my $out=$ssh->pipe_out("find $dir -name '*.eclass'");
    
  my %hash_eclass, %done_hash, %deja_vu;
  while($i=<$out>)
  {
	chomp $i;
 	#for each eclass
	my $inherit=$ssh->capture("grep '^[[:blank:]]*inherit' $i");
 	my @direct_dep=($inherit=~/(?<=inherit =)?(?: (\S+))/g);
	$hash_eclass{$i=~s/.*\/(.*?)\.eclass/\1/r}=\@direct_dep;
  }
  #now we have the first level dependency
 @queue_keys=(keys %hash_eclass);
  while(@queue_keys)
  {
	my $head= shift @queue_keys;
	#There is no work to be done on leafes 
 	#If its not a leaf walk the direct inherited dependencies 
	#and merge all lists
	my $done=1;
	my @new_inherited=();
	for my $iter (@{$hash_eclass{$head}})
	{
	      #il faut briser les dependances circulaires
	      unless ($deja_vu{$head}->{$iter})	      
	      {
	      	$deja_vu{$head}->{$iter}=1;
		merge_unique($hash_eclass{$head},$hash_eclass{$iter});
	      	$done=0;
		last;
	      }
	}
 	unless ($done)
	{
	#reschedule for later examination
	  push @queue_keys,$head;
	}
  }
  return \%hash_eclass
}

sub eclass2pckgn
{
  my ($ssh,$eclass)=@_;
  my %hash_eclass=&eclass_graph;
  my $dir=dirname($eclass);
  my $out=$ssh->pipe_out("find ${dir}/../ -type d -mindepth 2 -maxdepth 2");
  my @return;
  $eclass=~s:.*/(.*)\.eclass:\1:;
  while (my $atom=<$out>)
   {
     	chomp $atom;
	my $tmp=$ssh->capture("ls $atom/*.ebuild 2>/dev/null");
	next if ($ssh->error); 
  	my $filecontent=$ssh->capture("grep '^inherit *' $atom/*.ebuild");
	$filecontent=~s/.*inherit *//g;
	my @eclass=split /\s+/,$filecontent;;
	for (@eclass)
	  {
	    if(($_ eq $eclass)||(grep { $_ eq $eclass } @{$hash_eclass{$_}}))
	       {
		 push @return, ($atom=~s/.*\/(.*\/.*)/\1/r);
		}

	  }
   }
  return \@return;
}




sub compare_version;
sub parse_pkgdb_for_suffixes;
sub check_coherency
{
  my ($rev,$conffile,$ssh)=@_;
  my $log_str;
  $mypkgdb=$ssh->capture("cat /opt/clip-int/pkgdb/all.conf");
  print STDERR "Cannot open pkgdb!" and return if ($ssh->error);
  my %pkg=parse_pkgdb_for_suffixes($mypkgdb);
  $file=$ssh->capture("cat $ENV{'CLIP-SDK-CLIP-INT'}/portage-overlay-clip/$conffile/*.ebuild");
  #In clip*conf.ebuimd exacr versions are mentionned
  %hash=($file=~/^\s+=(.*\/.*)-(\d[^"]*?)$/mg);
  while(($k,$v)=each(%hash))
  { 
# print "clef $k version $v";
    $k=~s/_/-/g;
    $k=lc($k);
    if($pkg{$k.'-masked'} && !$pkg{$k})
    {
      $log_str.="$k  is masked\n";
      next;
    }
    $logstr.="[$conffile] $k is not present\n" and next unless ($pkg{$k});
#on compare les versions
    my $tmpval=compare_version($v,$pkg{$k}->{'version-clip'});
    if ($tmpval==-1) 
    { $logstr.="Update needed $k-$v to $k-".$pkg{$k}->{'version-clip'}."\n";}
    if ($tmpval==1) { $logstr.="$k is newer in $conffile " .
      "file\n\t$v > $pkg{$k}->{'version-clip'}\n";}
  }
  if (!$logstr)
  {
    $logstr="Nothing to notice\n";
  }

  make_path("$ENV{'CLIP-BUILDBOT-LOG-DIR'}/log/$rev/".dirname($conffile));;
  open($fic, ">", "$ENV{'CLIP-BUILDBOT-LOG-DIR'}/log/${rev}/".$conffile."-coherency.log") ;
  print $fic $logstr;
  close $fic;

}


  sub compare_version
  {
    my ($a,$b)=@_;
    my @a_comp=($a=~/(\D+|\d+|-r\d+)/g);
    my @b_comp=($b=~/(\D+|\d+|-r\d+)/g);
    my $res=0;
    for my $c (0..((@b_comp>@a_comp)?@a_comp-1:@b_comp-1))
    {
#       print "|$a_comp[$c]| vs |$b_comp[$c]|"; 
      if($a_comp[$c]=~/^\d+$/)
      {
#               print "chiffre";
	if($a_comp[$c]>$b_comp[$c])
	{
	  $res=1;
	  last;
	}
	if($a_comp[$c]<$b_comp[$c])
	{
	  $res=-1;
	  last;
	}
      }
      else
      {
#               print "lettre";
	if($a_comp[$c] gt $b_comp[$c])
	{
	  $res=1;
	  last;
	}
	if($a_comp[$c] lt $b_comp[$c])
	{
	  $res=-1;
	  last;
	}
      }
#       print "res $res";
    }
#print "res $res";
    return $res;
  }


  sub parse_pkgdb_for_suffixes
  {
    my @pkg=split /\n\n/,$_[0];
    my %pkg;
    for (@pkg)
    {
      s/\[(.*?)\.(\d+)\]\n//;
      $key=$1;
#
#Catch wild '_' and transforms them into gentle '-'
      $key=~s/_/-/g;
      $key=lc($key);
      my %j=/^(.*)\s+=\s+(.*)$/mg;
      my $k='clip-rm_deb_suffix';
      $key.="-masked" if ($j{'masked'});
      if ($j{$k})
      {
	for $suffix (map {s/\b_\b//r} (split /\s+/, $j{$k}))
	{
	  $suffix=~s/\.//g;
#               print $j{'category'}."/".$key.$suffix;
	  if($pkg{$j{'category'}."/".$key.$suffix})
	  {
	    warn("outch I already have one ".$j{'category'}."/".$key.$suffix) if($verbose);
	    next if(
		compare_version($pkg{$j{'category'}."/"
		  .$key.$suffix}{'version-clip'},
		  $j{'version-clip'})>=0)
	  }
	  $pkg{$j{'category'}."/".$key.$suffix}=\%j;#ici c'est des references
	}
      }
      else
      {
	if($pkg{$j{'category'}."/".$key})
	{
	  warn("outch I already have one ".$j{'category'}."/".$key) if ($verbose);
	  next if(
	      compare_version($pkg{$j{'category'}."/"
		.$key}{'version-clip'}, $j{'version-clip'})>=0)
	}
#       print $j{'category'}."/".$key;
	$pkg{$j{'category'}."/".$key}=\%j;#ici c'est des references
      }
    }
    return %pkg;
  }

sub update_local_mirror
{
  my $currentrev=shift;
  my $lastrev_inside=`cd $ENV{'CLIP-BUILDBOT-MASTER-LXC'}/rootfs/mnt/clip-int/ && LANG=C svn info --config-dir /var/lib/clip-buildbot/config`=~s/.*Revision: (\d+).*/\1/rs;
  my $filename=`mktemp`;
  $lastrev_inside++;
  if($lastrev_inside<=$currentrev)
  {
    system("cd $ENV{'CLIP-SVN-PATH'};".
	"svnrdump dump https://clip.ssi.gouv.fr/clip-int".
	" -r $lastrev_inside:$currentrev --incremental --config-dir /var/lib/clip-buildbot/config >$filename");
    system("svnadmin load $ENV{'CLIP-MIRROR-PATH'} <$filename");
    system("rm $filename");
    system("cd $ENV{'CLIP-BUILDBOT-MASTER-LXC'}/rootfs/mnt/clip-int/ && svn up");
  }
}


sub update_mirror
{
  print "Dans update mirror";
  my ($ssh_test,$confstem)=@_;
#the .deb from test-sdkhas already been uploaded to mirror-sdk
#reconstruct mirror 
  my $error;
  #my ($dist,$apps_or_core,$version)=($conffile=~/clip-conf\/(rm|clip)-(apps|core)-(.*)\.ebuild/);
  my ($dist,$apps_or_core,$version)=($confstem=~/clip-conf\/(rm|clip)-(apps|core)-(.*)/);
 my $conffile=<$ENV{'CLIP-BUILDBOT-MIRROR-LXC'}/rootfs//home/lambda/build/debs/$dist/$dist-$apps_or_core-conf_*.deb>;
  #my ($dist,$apps_or_core,$version)=($conffile=~/clip-conf\/(rm|clip)-(apps|core)-(.*)/);
#first copy .debs to ephemeral container
# gm -p /home/lambda/build/debs/rm/ -R tmpmirror/ -D clip -d rm-core-conf_4.4.3-r17_i386.deb
#
#ok let's take the basename of the -conf deb
$conffile=~s/.*\///;

  {
   my $launchtext=`/usr/share/clip-buildbot/bin/wrapper-lxc-mirror-start 2>&1`;
   my $name=($launchtext=~s/.*\/(.*?)\/rootfs.*/\1/sr);
   my $ip=($launchtext=~s/.*IP.*?((\d{1,3}\.){3}\d{1,3}).*/\1/sr);
   my $ssh_mirror=Net::OpenSSH->new("$ip",user => 'root', password => 'root',
   			master_opts =>[-o => "UserKnownHostsFile=/etc/clip-buildbot/creds/sdk_keys" , -o => "StricthostKeyChecking=no"] ) or die "Can't ssh to the SDK";
  print("/opt/clip-livecd/get-mirrors.sh -p ".
  	"/home/lambda/build/debs/$dist -R /localmirror -D $dist -d $conffile");
  my $out=$ssh_mirror->capture("/opt/clip-livecd/get-mirrors.sh -p ".
  	"/home/lambda/build/debs/$dist -R /localmirror -D $dist -d $conffile 2>\&1");
	#$dist-$apps_or_core-$version.deb");
  $error=$ssh_mirror->error;
  print $out;
   system("/usr/share/clip-buildbot/bin/wrapper-lxc-mirror-stop $name");
  }
#
#  If the build of the mirror is possible 
#  do it for real 
  if ($error)
  {
    print "Could not rebuild mirror : $dist ";
  }
  else
  {
#do it for true
    my $launchtext=`/usr/share/clip-buildbot/bin/wrapper-lxc-update-start 2>&1`;
#IP address is 69
    my $ssh_mirror=Net::OpenSSH->new("$ip",user => 'root', password => 'root',
     master_opts =>[-o => "UserKnownHostsFile=/etc/clip-buildbot/creds/sdk_keys"
     , -o => "StricthostKeyChecking=no"]) or die "Can't ssh to the SDK";
    $ssh_mirror->capture("/opt/clip-livecd/get-mirrors.sh -p ".
	"/home/lambda/build/debs/$dist -R /mirror -D $dist -d $conffile");
    system("/usr/share/clip-buildbot/bin/wrapper-lxc-update-stop");
  }
  system("rm -rf $tmpdir");

}

sub sendmail_to_commiter
{
#  my $email=shift;
#  my $smtp=Net::SMTP->new($ENV{'SMTP Server'});
#  $smtp->mail("buildbot@clip.ssi.gouv.fr");
#  $smtp->to("$email\@ssi.gouv.fr");
#  $smtp->data();
#  $smtp->datasend("Your commit $rev Did not compile");
#  $smtp->dataend();
#  $smtp->quit();
}


#
# This code is borrowed to the Wonderfull tool of V. Strubel clip-build
# 
#
#
my $g_cli_opts = {};

sub preprocessSpec ($) {
  my $in = shift;

  die "No spec specified !" unless ($in);

  my $tmpname = $ENV{'TMPDIR'};
  $tmpname = "/tmp" unless ($tmpname);

  my $basename;
  if ($in =~ /\.*\/([^\/]+)/) {
    $basename = $1;
  } else {
    $basename = $in;
  }

  my $out = `mktemp $tmpname/$basename.XXXXXX`;
  chomp $out;
  die "mktemp $tmpname/$basename failed" unless ($out);

  my @cmd = ("clip-specpp", "-i", $in, "-o", $out);

  push @cmd, ("-defs", $g_cli_opts->{'defines'}) if ($g_cli_opts->{'defines'});
  my $ret = system(@cmd);
  die "Preprocessing of $in failed" if ($ret);

  return $out;
}

sub ssh_preprocessSpec ($$) {
  my ($ssh,$in)=@_;

  die "No spec specified !" unless ($in);

  my $tmpname = $ENV{'TMPDIR'};
  $tmpname = "/tmp" unless ($tmpname);

  my $basename=$in;
  $basename=~ s/.*\///;

  my $out = $ssh->capture("mktemp $tmpname/$basename.XXXXXX");
  chomp $out;
  die "mktemp $tmpname/$basename failed" unless ($out);

  my @cmd = ("clip-specpp", "-i", $in, "-o", $out);

  push @cmd, ("-defs", $g_cli_opts->{'defines'}) if ($g_cli_opts->{'defines'});
  $ssh->capture("@cmd");
  die "Preprocessing of $in failed" if ($ssh->error);

  return $out;
}

# Parse specfile, return a reference to a hash representation of
# spec on success
sub parseSpec ($) {
  my $filename = shift;

  die "$filename not readable;"
    if (not -r $filename or not -f $filename);

#my $xml = new XML::Simple or die "Cannot allocate XML parser;";
  open my $fh, $filename;
  binmode $fh;
  my $spec = XML::LibXML->load_xml(IO => $fh)
    or die "Error parsing XML spec;";
  return $spec;
}

# Parse specfile _as a string_, return a reference to a hash representation of
# spec on success
sub parseSpecString ($) {
  my $string = shift;

#my $xml = new XML::Simple or die "Cannot allocate XML parser;";
  open my $fh, $filename;
  binmode $fh;
  my $spec = XML::LibXML->load_xml(string => $string)
    or die "Error parsing XML spec;";
  return $spec;
}

sub isinspecfile
{
  my ($ssh,$atom)=@_;
  my $retval = sub { 
    	my $tmpfilename=ssh_preprocessSpec($ssh,$_[0]);
	my $spec=parseSpecString($ssh->capture("cat $tmpfilename"));
	my @nodes=$spec->find("//pkgnames[contains(self::pkgnames,'"
					.$atom."')]")->get_nodelist();
	return 0+grep {$_->string_value=~/^\s*$atom\s*$/m} @nodes;
    };
  return $retval;
}

sub specs_having
{
  my ($ssh,$atom)=@_;
  @specfiles=split /\s+/, $ssh->capture("find /opt/clip-int/specs -iname '*.xml' ! -wholename '*include*'");

#
#
#  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK 
#  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK 
#  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK 
#  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK  UGLY HACK 
#
#
#I donno want to deal withother species as only one sdk-mirror is available
 @specfiles=grep {/\/specs\/clip-rm/} @specfiles;


 my $sub_test=&isinspecfile;
   return grep {$sub_test->($_)}  @specfiles;
}

sub start_sdk_test_ssh
#
# takes $names as first paramter AND MODIFIES IT!!!!!
#
{
	my $launchtext=`/usr/share/clip-buildbot/bin/wrapper-lxc-test-start 2>&1`;
   	$_[0]=($launchtext=~s/.*\/(.*?)\/rootfs.*/\1/sr);
   	my $ip=($launchtext=~s/.*IP.*?((\d{1,3}\.){3}\d{1,3}).*/\1/sr);
	my $ssh=Net::OpenSSH->new("$ip",user => 'root', password => 'root',
        master_opts =>[-o => "UserKnownHostsFile=/etc/clip-buildbot/creds/sdk_keys" ,     
        -o => "StricthostKeyChecking=no"]) or die "Can't ssh to the SDK";
  	return $ssh;
}

1;
