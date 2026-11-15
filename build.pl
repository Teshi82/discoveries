#!/usr/bin/perl
# Builds the static site, one copy per language:
#   docs/<lang>/index.html            the top page
#   docs/<lang>/<place>/index.html    one detail page per destination
#
#   Source:  src/template.html  (top page, with Japanese text and data-i18n keys)
#            src/i18n.json      (top-page translations for the other languages)
#            src/place.html     (detail-page layout, with {{placeholders}})
#            src/places.json    (detail-page text for every language, and official links)
#   Output:  docs/              (the folder GitHub Pages serves)
#
# Usage, from Git Bash in this folder:
#   perl build.pl                                  # relative links (local preview)
#   perl build.pl https://USER.github.io/REPO      # absolute links + sitemap (for publishing)
use strict;
use warnings;
use utf8;
use JSON::PP;
use File::Path qw(make_path);
use File::Basename qw(dirname);

my $base = shift // '';
$base =~ s{/+$}{};
my $dir = dirname(__FILE__);

# [ language code, folder name, Open Graph locale ]
my @langs = (
  ['ja',      'ja',      'ja_JP'],
  ['en',      'en',      'en_US'],
  ['zh-Hans', 'zh-hans', 'zh_CN'],
  ['zh-Hant', 'zh-hant', 'zh_TW'],
  ['fr',      'fr',      'fr_FR'],
  ['es',      'es',      'es_ES'],
);

sub slurp {
  my ($path, $layer) = @_;
  open my $fh, "<$layer", $path or die "Cannot read $path: $!";
  local $/;
  return <$fh>;
}
sub spit {
  my ($path, $text) = @_;
  make_path(dirname($path));
  open my $fh, '>:raw:encoding(UTF-8)', $path or die "Cannot write $path: $!";
  print $fh $text;
  close $fh;
}
sub esc {
  my $s = shift;
  $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
  return $s;
}

my $tpl       = slurp("$dir/src/template.html", ':encoding(UTF-8)');
my $place_tpl = slurp("$dir/src/place.html", ':encoding(UTF-8)');
my $dict      = JSON::PP->new->utf8->decode(slurp("$dir/src/i18n.json", ':raw'));
my $pdata     = JSON::PP->new->utf8->decode(slurp("$dir/src/places.json", ':raw'));
my @places    = @{ $pdata->{places} };

# $depth = how many folders below docs/ the page sits (1 = top page, 2 = detail page)
sub page_url {
  my ($slug, $page, $depth) = @_;
  return $base ne '' ? "$base/$slug/$page" : ('../' x $depth) . "$slug/$page";
}

# Replaces data-i18n text with the translation for the language, and fills in the <head>.
sub localize {
  my ($html, $l, $page, $depth, $image) = @_;
  my ($code, $slug, $locale) = @$l;
  my $d = $code eq 'ja' ? undef : ($dict->{$code} or die "No translations for $code");
  my $tr = sub {
    my ($key, $original) = @_;
    return $original unless $d;
    defined $d->{$key} or die "Missing translation: $code / $key";
    return esc($d->{$key});
  };

  # Element text:  <tag data-i18n="key">text</tag>
  $html =~ s{(<(\w+)\b[^>]*?)\s+data-i18n="([^"]+)"([^>]*>)(.*?)(</\2>)}{$1 . $4 . $tr->($3, $5) . $6}gse;
  # Attribute text:  <meta data-i18n-content="key" content="text">
  $html =~ s{\s+data-i18n-content="([^"]+)"(\s+content=")([^"]*)(")}{$2 . $tr->($1, $3) . $4}gse;

  $html =~ s{<html lang="[^"]*"}{<html lang="$code"};
  $html =~ s{<option value="\Q$code\E">}{<option value="$code" selected>};

  my ($title) = $html =~ m{<title>(.*?)</title>}s;
  my ($desc)  = $html =~ m{<meta name="description" content="([^"]*)"};
  my $root_url = $base ne '' ? "$base/" : '../' x $depth;

  my @head;
  push @head, qq{<link rel="canonical" href="} . page_url($slug, $page, $depth) . qq{">};
  push @head, qq{<link rel="alternate" hreflang="$_->[0]" href="} . page_url($_->[1], $page, $depth) . qq{">} for @langs;
  push @head, qq{<link rel="alternate" hreflang="x-default" href="} . ($page eq '' ? $root_url : page_url('en', $page, $depth)) . qq{">};
  push @head, qq{<meta property="og:type" content="website">};
  push @head, qq{<meta property="og:site_name" content="DISCOVERIES">};
  push @head, qq{<meta property="og:title" content="$title">};
  push @head, qq{<meta property="og:description" content="$desc">};
  push @head, qq{<meta property="og:locale" content="$locale">};
  if ($base ne '') {
    push @head, qq{<meta property="og:url" content="} . page_url($slug, $page, $depth) . qq{">};
    push @head, qq{<meta property="og:image" content="$base/img/$image">};
    push @head, qq{<meta name="twitter:card" content="summary_large_image">};
  }
  my $head = join("\n", @head);
  $html =~ s{<!--HEAD_LINKS-->}{$head};
  return $html;
}

# Name and area of a destination: Japanese lives in places.json, the rest in i18n.json (d1.name ...)
sub place_label {
  my ($p, $code, $field) = @_;
  my $v = $code eq 'ja' ? $p->{ja}{$field} : $dict->{$code}{"$p->{key}.$field"};
  defined $v or die "Missing $field for $p->{slug} / $code";
  return $v;
}

my @pages;   # every page, for the sitemap

for my $l (@langs) {
  my ($code, $slug) = @$l;

  spit("$dir/docs/$slug/index.html", localize($tpl, $l, '', 1, 'hero.jpg'));
  push @pages, [$slug, ''];
  print "built docs/$slug/index.html\n";

  my $ui = $pdata->{ui}{$code} or die "No detail-page labels for $code";
  for my $p (@places) {
    my $t = $p->{$code} or die "No detail text for $p->{slug} / $code";
    my %v = (
      slug => $p->{slug},
      img  => $p->{img},
      name => esc(place_label($p, $code, 'name')),
      area => esc(place_label($p, $code, 'area')),
    );
    for my $k (qw(lead intro season access stay tip)) {
      defined $t->{$k} or die "Missing $k for $p->{slug} / $code";
      $v{$k} = esc($t->{$k});
    }
    $v{"ui.$_"} = esc($ui->{$_}) for keys %$ui;

    $v{highlights} = join("\n", map {
      "      <li><h3>" . esc($_->[0]) . "</h3><p>" . esc($_->[1]) . "</p></li>"
    } @{ $t->{h} });

    $v{links} = join("\n", map {
      my ($label, $href) = @{ $code eq 'ja' ? $_->{ja} : $_->{intl} };
      qq{      <li><a href="$href" target="_blank" rel="noopener">} . esc($label) . qq{<span aria-hidden="true"> ↗</span></a></li>};
    } @{ $p->{links} });

    $v{others} = join("\n", map {
      qq{      <a class="other" href="../$_->{slug}/"><img src="../../img/$_->{img}" alt="" loading="lazy"><span>}
        . esc(place_label($_, $code, 'name')) . qq{</span></a>};
    } grep { $_->{slug} ne $p->{slug} } @places);

    my $html = $place_tpl;
    $html =~ s{\{\{([\w.]+)\}\}}{ defined $v{$1} ? $v{$1} : die "Unknown placeholder {{$1}} in src/place.html" }ge;

    my $page = "$p->{slug}/";
    spit("$dir/docs/$slug/${page}index.html", localize($html, $l, $page, 2, $p->{img}));
    push @pages, [$slug, $page];
  }
  print "built docs/$slug/<place>/index.html x " . scalar(@places) . "\n";
}

if ($base ne '') {
  my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
  $xml .= "  <url><loc>" . page_url($_->[0], $_->[1], 1) . "</loc></url>\n" for @pages;
  $xml .= "</urlset>\n";
  spit("$dir/docs/sitemap.xml", $xml);
  spit("$dir/docs/robots.txt", "User-agent: *\nAllow: /\nSitemap: $base/sitemap.xml\n");
  print "built docs/sitemap.xml and docs/robots.txt for $base\n";
}
