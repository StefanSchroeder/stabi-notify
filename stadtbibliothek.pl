#!/usr/bin/perl 
use WWW::Mechanize;
use WWW::Mechanize::FormFiller;
use Date::Calc qw(Delta_Days);
use HTML::TableExtract;
use URI::URL;
use HTTP::Cookies;
use YAML::XS 'LoadFile';
use Data::Dumper;
use Getopt::Long;

my $textmode;

GetOptions ("text"  => \$textmode);

my $debug = 0;
my $Number; # The ID that is used for Login to the website.
my $Password; # The password that is used for Login to the website.
my $Nickname; 

my $homedir = $ENV{"HOME"};
die("ERROR: You have no home-dir. Cannot continue.") unless(-d $homedir);

my $config_filename = $homedir . '/.stadtbibliothek_passwords.yaml';

if (not -f $config_filename)
{
    system("cp stadtbibliothek_passwords.template.yaml $config_filename");
    print("This script was started for the first time. Please edit $config_filename now.\n");
    exit 1;
}

my $config = LoadFile($config_filename);

($Nickname) = @ARGV;
die("ERROR: You have to pass a name from the configuration as argument.\n") unless($Nickname);

foreach my $item (@$config)
{
    if ($item->{'name'} eq $Nickname)
    {
        $Number = $item->{'number'};
        $Password = $item->{'password'};
        last;
    }
}

die("Missing number for $Nickname.\n") unless($Number);
die("Missing password for $Nickname.\n") unless($Password);

warn "Name = $Nickname\n";
warn "ID = $Number\n";

###################################################
## Fetch
###################################################
#my $agent      = WWW::Mechanize->new( cookie_jar => $cookie_jar );
my $cookie_jar = HTTP::Cookies->new;
my $agent = WWW::Mechanize->new( autocheck => 1, cookie_jar => $cookie_jar  );
$agent->agent_alias( 'Linux Mozilla' );

$cookie_jar->set_cookie( "scrW"=>"1280", "cphpx"=>"1564px", "lpcshpx"=>"1495px" );
$agent->add_header( "Cookie" => "scrW=1280; cphpx=564px; lpcshpx=495px;" );

my $formfiller = WWW::Mechanize::FormFiller->new();
$agent->env_proxy();

$agent->get('https://bibliothek.hannover-stadt.de/alswww3.dll/APS_ZONES?fn=RenewMyLoans');
$agent->form_number(1) if $agent->forms and scalar @{$agent->forms};
$agent->form_number(2);

$formfiller->add_filler( 'BRWR' => Fixed => $Number );
$formfiller->add_filler( 'PIN' => Fixed => $Password );

$formfiller->fill_form($agent->current_form);

$agent->submit();

$agent->form_number(1) if $agent->forms and scalar @{$agent->forms};
$agent->follow_link('text_regex' => qr((?^:Verbuchungen)));

###################################################
## Process
###################################################
my $te = HTML::TableExtract->new();

$te->parse($agent->content);

warn Dumper $agent->content if ($debug);

my @now = localtime;
($d1, $m1, $y1) = @now[3,4,5];
$m1 += 1; # Month are offset 0
$y1 += 1900; # Years are offset 1900

my %pool;
my $daymap;
foreach $ts ($te->tables)  # Look at all tables.
{
    foreach $row ($ts->rows) 
    {
        if ($$row[5] =~ m{\d\d/\d\d/20\d\d})
        {
            $title = $$row[0];
            $title =~ s/\s+/ /g;
            $title =~ s/^\s/ /;
            $retur = $$row[5];
            $retur =~ s/\s+/ /g;
            my $annotation = "";
            if ($retur =~ m{(\d\d)/(\d\d)/(20\d\d)})
            {
                my $d2 = $1;
                my $m2 = $2;
                my $y2 = $3;
                my $days = Delta_Days( $y1, $m1, $d1, $y2, $m2, $d2);
                $daymap{$days} = $retur;
                push @{$pool{$days}}, "=> $title\n";
            }
        }
    }
}

my $note = "$Nickname\n";
my @paragraph;
for my $k (sort {$a <=> $b} keys %pool)
{
    $annotation = sprintf "In $k Tagen.";
    $annotation = sprintf "HEUTE" if ($k == 0);
    $annotation = sprintf "Vor %d Tagen", -$k if ($k < 0);
    push @paragraph, "Abgabe $daymap{$k} ($annotation)\n" .
        join("",@{$pool{$k}});
}
$note .= join("\n", @paragraph);
#$note =~ s/&/_/g;
#warn "$note\n";

if($textmode)
{
    print $note;
}
else
{
    system(qq{notify-send -t 0 "$note"});
}

