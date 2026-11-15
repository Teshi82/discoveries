#!/usr/bin/perl
# Builds one static page per language: docs/<lang>/index.html
#
#   Source:  src/template.html  (the page, with Japanese text and data-i18n keys)
#            src/i18n.json      (translations for the other languages)
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

my $tpl  = slurp("$dir/src/template.html", ':encoding(UTF-8)');
my $dict = JSON::PP->new->utf8->decode(slurp("$dir/src/i18n.json", ':raw'));

my $url = sub { my $slug = shift; $base ne '' ? "$base/$slug/" : "../$slug/" };
my $root_url = $base ne '' ? "$base/" : "../";

for my $l (@langs) {
  my ($code, $slug, $locale) = @$l;
  my $d = $code eq 'ja' ? undef : ($dict->{$code} or die "No translations for $code");
  my $html = $tpl;
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

  $html =~ s{<html lang="[^"]*">}{<html lang="$code">};
  $html =~ s{<option value="\Q$code\E">}{<option value="$code" selected>};

  my ($title) = $html =~ m{<title>(.*?)</title>}s;
  my ($desc)  = $html =~ m{<meta name="description" content="([^"]*)"};

  my @head;
  push @head, qq{<link rel="canonical" href="} . $url->($slug) . qq{">};
  push @head, qq{<link rel="alternate" hreflang="$_->[0]" href="} . $url->($_->[1]) . qq{">} for @langs;
  push @head, qq{<link rel="alternate" hreflang="x-default" href="$root_url">};
  push @head, qq{<meta property="og:type" content="website">};
  push @head, qq{<meta property="og:site_name" content="Irodori Japan">};
  push @head, qq{<meta property="og:title" content="$title">};
  push @head, qq{<meta property="og:description" content="$desc">};
  push @head, qq{<meta property="og:locale" content="$locale">};
  if ($base ne '') {
    push @head, qq{<meta property="og:url" content="} . $url->($slug) . qq{">};
    push @head, qq{<meta property="og:image" content="$base/img/hero.jpg">};
    push @head, qq{<meta name="twitter:card" content="summary_large_image">};
  }
  my $head = join("\n", @head);
  $html =~ s{<!--HEAD_LINKS-->}{$head};

  spit("$dir/docs/$slug/index.html", $html);
  print "built docs/$slug/index.html\n";
}

if ($base ne '') {
  my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
  $xml .= "  <url><loc>" . $url->($_->[1]) . "</loc></url>\n" for @langs;
  $xml .= "</urlset>\n";
  spit("$dir/docs/sitemap.xml", $xml);
  spit("$dir/docs/robots.txt", "User-agent: *\nAllow: /\nSitemap: $base/sitemap.xml\n");
  print "built docs/sitemap.xml and docs/robots.txt for $base\n";
}
