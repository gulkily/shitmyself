#!/usr/bin/perl -T

use strict;
use warnings;
use 5.010;

require_once('token_defs.pl');

sub IndexTextFile { # $file | 'flush' ; indexes one text file into database
# Reads a given $file, parses it, and puts it into the index database
# If ($file eq 'flush'), flushes any queued queries
# Also sets appropriate task entries
	WriteLog('IndexTextFile() BEGINS');

	my @indexMessageLog; # @parseLog @indexLog

	state $SCRIPTDIR = GetDir('script');
	state $HTMLDIR = GetDir('html');
	state $TXTDIR = GetDir('txt');

	WriteLog('IndexTextFile: $SCRIPTDIR = ' . $SCRIPTDIR . '; $HTMLDIR = ' . $HTMLDIR . '; $TXTDIR = ' . $TXTDIR);

	my $file = shift;
	chomp($file);

	my %flags;
	my $flagsReference = shift;
	if ($flagsReference) {
		%flags = %{$flagsReference};
	}

	WriteLog('IndexTextFile: $file = ' . $file);

	if ($file eq 'flush') {
		WriteLog("IndexTextFile(flush)");
		DBAddKeyAlias('flush');
		DBAddItem('flush');
		DBAddVoteRecord('flush');
		DBAddItemParent('flush');
		DBAddPageTouch('flush');
		DBAddTask('flush');
		DBAddConfigValue('flush');
		DBAddItemAttribute('flush');
		DBAddLocationRecord('flush');
		return 1; # called with ('flush')
	}

	push @indexMessageLog, 'indexing begins';

	if (GetConfig('admin/organize_files') && !$flags{'skip_organize'}) {
		# renames files to their hashes
		my $newFile = OrganizeFile($file);

		if ($file ne $newFile) {
			push @indexMessageLog, 'file was organized (moved location, changed filename)';
		}
	}

	my $fileHash = ''; # hash of file contents
	$fileHash = GetFileHash($file); #IndexTextFile()

	push @indexMessageLog, 'file hash = ' . $fileHash;

	if (GetConfig('admin/index/stat_file')) { #todo this should only be in one place
		my @fileStat = stat($file);
		my $fileSize =    $fileStat[7]; #file size
		my $fileModTime = $fileStat[9];

		if ($fileSize && $fileModTime) {
			push @indexMessageLog, 'file stat: size = ' . $fileSize . '; mod time = ' . $fileModTime;
		} else {
			WriteLog('IndexTextFile: warning: stat_file $fileSize or $fileModTime is FALSE; $file = ' . $file . '; caller = ' . join(',', caller));
		}
	}

	my $titleCandidate = '';

	if (!$file || !$fileHash) {
		WriteLog('IndexTextFile: warning: $file or $fileHash missing; returning');
		WriteLog('IndexTextFile: warning: $file = ' . ($file ? $file : 'FALSE'));
		WriteLog('IndexTextFile: warning: $fileHash = ' . ($fileHash ? $fileHash : 'FALSE'));
		return ''; # failed sanity check
	}

	# if the file is present in deleted.log, get rid of it and its page, return
	if (IsFileDeleted($file, $fileHash)) {
		# write to log
		WriteLog('IndexTextFile: IsFileDeleted() returned true, returning');
		if ($file) {
			WriteLog('IndexTextFile: IsFileDeleted($file) = true; $file = ' . $file);
		}
		if ($fileHash) {
			WriteLog('IndexTextFile: IsFileDeleted($file) = true; $fileHash = ' . $fileHash);
		}
		push @indexMessageLog, 'found in deleted log';
		return 0; # deleted.log IsFileDeleted($file, $fileHash)
	}

	my $addedTime = 0;

	WriteLog('IndexTextFile: $fileHash = ' . $fileHash);
	if (GetConfig('admin/logging/write_chain_log')) {
		$addedTime = AddToChainLog($fileHash); # IndexTextFile();
		WriteLog('IndexTextFile: $addedTime from AddToChainLog($fileHash) = ' . $addedTime);
	} else {
		$addedTime = GetTime(); #todo make nicer
		WriteLog('IndexTextFile: $addedTime from GetTime() = ' . $addedTime);
	}

	if (GetCache('indexed/' . $fileHash)) {
		WriteLog('IndexTextFile: already indexed, returning. $fileHash = ' . $fileHash);
		return $fileHash; # already indexed
	}

	my $authorKey = '';

	if (substr(lc($file), length($file) -4, 4) eq ".txt") {
		if (GetConfig('admin/gpg/enable')) {
			$authorKey = GpgParse($file) || '';
		}
		my $message = GetFileMessage($file);
		#$message = trim($message); # to be considered

		if (!defined($message) || !$message) {
			WriteLog('IndexTextFile: warning: $message was not defined, setting to empty string');
			$message = '';
		}

		if (
			GetConfig('admin/index/filter_common_noise')
		) {
			if (
				$message =~ m/^[0-9a-f][0-9a-f]\/[0-9a-f][0-9a-f]\/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\.html$/
				||
				$message =~ m/^[0-9a-f][0-9a-f]\/[0-9a-f][0-9a-f]\/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\.html\?message=[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/
				||
				$message =~ m/^\<a href=\"item\?id.+\"\>.+\<\/a\>$/
			) {
				# items matching these are typically added via
				# 404 handler looking at clients trying to access
				# expired or deleted resources and can be discarded
				{
					# this is how we delete a file
					AppendFile('log/deleted.log', $fileHash);
					if (IsFileDeleted($file, $fileHash)) {
						#cool
					}
				}

				WriteLog('IndexTextFile: Flagged by common noise filter, returning');

				return 0; # GetConfig('admin/index/filter_common_noise')
			} # common noise detected
		} # GetConfig('admin/index/filter_common_noise')

		my $detokenedMessage = $message; # message with tokens removed/replaced
		my %hasToken; # all tokens found in message

		push @indexMessageLog, '---';

		if ($detokenedMessage && GetConfig('setting/admin/token/scunthorpe')) {
			my %text;
			$text{'message'} = $message;
			$text{'messageLog'} = \@indexMessageLog;
			$text{'fileHash'} = $fileHash;

			require_once('scunthorpe.pl');
			my $textRef = IndexScunthorpe(\%text);
			%text = %{$textRef};

			#$message = $text{'message'};
			@indexMessageLog = @{$text{'messageLog'}};
			$fileHash = $text{'fileHash'};
		} # scunthorpe

		if ($detokenedMessage && GetConfig('setting/admin/token/puzzle')) {
			my %text;
			$text{'message'} = $message;
			$text{'detokenedMessage'} = $detokenedMessage;
			$text{'messageLog'} = \@indexMessageLog;
			$text{'fileHash'} = $fileHash;
			$text{'authorKey'} = $authorKey;

			require_once('puzzle.pl');
			my $textRef = IndexPuzzle(\%text);
			%text = %{$textRef};

			$message = $text{'message'};
			$detokenedMessage = $text{'detokenedMessage'};
			@indexMessageLog = @{$text{'messageLog'}};
			$fileHash = $text{'fileHash'};
		} # puzzle

		#WriteLog('IndexTextFile: pass1: $message = ' . length($message) . '; $detokenedMessage = ' . length($detokenedMessage));

		my @tokenMessages;
		my @tokensFound;
		{ #tokenize into @tokensFound
			###################################################
			# TOKEN FIRST PASS PARSING BEGINS HERE
			# token: identifier
			# mask: token string, separator, parameter
			# params: parameters for regex matcher
			# message: what's displayed in place of token for user
			my @tokenDefs = GetTokenDefs();

			# parses standard issue tokens, definitions above
			# stores into @tokensFound

			my $limitTokensPerFile = int(GetConfig('admin/index/limit_tokens_per_file'));
			if (!$limitTokensPerFile) {
				$limitTokensPerFile = 500;
			}

			#todo sanity check on $limitTokensPerFile;

			foreach my $tokenDefRef (@tokenDefs) {
				my %tokenDef = %$tokenDefRef;
				my $tokenName = $tokenDef{'token'};
				my $tokenMask = $tokenDef{'mask'};
				my $tokenMaskParams = $tokenDef{'mask_params'};
				my $tokenMessage = $tokenDef{'message'};

				#push @indexMessageLog, 'looking for: ' . $tokenMask . '(' . $tokenName . ')';

				#WriteLog('IndexTextFile: pass2: $message = ' . length($message) . '; $detokenedMessage = ' . length($detokenedMessage));

				if (GetConfig("admin/token/$tokenName") && $detokenedMessage) {
					WriteLog('IndexTextFile: $tokenName = ' . $tokenName . '; $tokenMask = ' . $tokenMask);
					# token is enabled, and there is still something left to parse

					my @tokenLines;

					################
					# NOTE
					# if you see a problem with these lines, look in token_defs.pl

					WriteLog('IndexTextFile: $tokenMask = ' . $tokenMask . '; $tokenMaskParams = ' . $tokenMaskParams);

					#WriteLog('IndexTextFile: $detokenedMessage = ' . $detokenedMessage);

					if ($tokenMaskParams eq 'mg') {
						# probably an easier way to do this, but i haven't found it yet
						@tokenLines = ($detokenedMessage =~ m/$tokenMask/mg);
					} elsif ($tokenMaskParams eq 'mgi') {
						@tokenLines = ($detokenedMessage =~ m/$tokenMask/mgi);
					} elsif ($tokenMaskParams eq 'gi') {
						@tokenLines = ($detokenedMessage =~ m/$tokenMask/gi);
					} elsif ($tokenMaskParams eq 'g') {
						@tokenLines = ($detokenedMessage =~ m/$tokenMask/g);
					} else {
						WriteLog('IndexTextFile: warning: sanity check failed: $tokenMaskParams not in approved list');
						@tokenLines = ();
					}

					WriteLog('IndexTextFile: $tokenName = ' . $tokenName . '; lines: ' . join(',', @tokenLines));

					if (scalar(@tokensFound) + scalar(@tokenLines) > $limitTokensPerFile * 2) {
						# i don't remember why both are counted here...
						WriteLog('IndexTextFile: warning: found too many tokens, skipping. $file = ' . $file . '; count = ' . (scalar(@tokensFound)+scalar(@tokenLines)));
						push @indexMessageLog, 'token limit reached, no more tokens will be processed!';
						last; # not a return, but should be searchable as one
					} else {
						WriteLog('IndexTextFile: sanity check passed');
					}

					while (@tokenLines) {
						my $foundTokenName = shift @tokenLines;
						if (!$foundTokenName) {
							WriteLog('IndexTextFile: warning: $foundTokenName is FALSE');
						} else {
							my $foundTokenSpacer = shift @tokenLines;
							if (!$foundTokenSpacer) {
								WriteLog('IndexTextFile: warning: $foundTokenSpacer is FALSE');
								$foundTokenSpacer = '';
							}

							my $foundTokenParam = shift @tokenLines;
							if (!$foundTokenParam) {
								WriteLog('IndexTextFile: warning: $foundTokenParam is FALSE');
								$foundTokenParam = '';
							}

							$foundTokenParam = trim($foundTokenParam);

							my $reconLine = $foundTokenName . $foundTokenSpacer . $foundTokenParam; #todo #bughere
							WriteLog('IndexTextFile: warning: my $reconLine = $foundTokenName . $foundTokenSpacer . $foundTokenParam; #todo #bughere');
							WriteLog('IndexTextFile: warning: $reconLine = ' . $reconLine);
							#WriteLog('IndexTextFile: token/' . $tokenName . ' : ' . $reconLine);

							push @indexMessageLog, 'found token: ' . $tokenName . ', ' . $foundTokenSpacer . ', ' . $foundTokenParam;

							my %newTokenFound;
							$newTokenFound{'token'} = $tokenName;
							$newTokenFound{'spacer'} = $foundTokenSpacer;
							$newTokenFound{'param'} = $foundTokenParam;
							$newTokenFound{'recon'} = $reconLine;
							$newTokenFound{'message'} = $tokenMessage;
							$newTokenFound{'apply_to_parent'} = $tokenDef{'apply_to_parent'};
							$newTokenFound{'target_attribute'} = $tokenDef{'target_attribute'};
							push(@tokensFound, \%newTokenFound);

							if ($tokenName eq 'hashtag' || $tokenName eq 'plustag') {
								$hasToken{$foundTokenParam} = 1;
							}

							$detokenedMessage = str_replace($reconLine, '', $detokenedMessage);
						}
					} # while (@tokenLines)
				} # GetConfig("admin/token/$tokenName") && $detokenedMessage
			} # @tokenDefs

			# TOKEN FIRST PASS PARSING ENDS HERE
			# @tokensFound now has all the found tokens
			WriteLog('IndexTextFile: scalar(@tokensFound) = ' . scalar(@tokensFound));
			###################################################

			if (GetConfig('setting/admin/token/http')) {
				my @httpMatches = ($detokenedMessage =~ m/(http:\S+)/mg);

				while (@httpMatches) {
					my $httpMatch = shift @httpMatches;
					#$detokenedMessage = str_replace($httpMatch, '[http]', $detokenedMessage);
					#DBAddItemAttribute($fileHash, 'http', $httpMatch);

					my %newTokenFound;
					$newTokenFound{'token'} = 'http';
					#$newTokenFound{'spacer'} = '';
					$newTokenFound{'param'} = $httpMatch;
					$newTokenFound{'recon'} = $httpMatch;
					$newTokenFound{'message'} = '[http]';
					$newTokenFound{'target_attribute'} = 'http';
					push(@tokensFound, \%newTokenFound);
					push @indexMessageLog, 'found http address';
				}
			} # http token
			if (GetConfig('setting/admin/token/https')) {
				my @httpMatches = ($detokenedMessage =~ m/(https:\S+)/mg);

				while (@httpMatches) {
					my $httpMatch = shift @httpMatches;
					#$detokenedMessage = str_replace($httpMatch, '[http]', $detokenedMessage);
					#DBAddItemAttribute($fileHash, 'http', $httpMatch);

					my %newTokenFound;
					$newTokenFound{'token'} = 'https';
					#$newTokenFound{'spacer'} = '';
					$newTokenFound{'param'} = $httpMatch;
					$newTokenFound{'recon'} = $httpMatch;
					$newTokenFound{'message'} = '[https]';
					$newTokenFound{'target_attribute'} = 'https';
					push(@tokensFound, \%newTokenFound);
					push @indexMessageLog, 'found https address';
				}
			} # http token

			push @indexMessageLog, 'finished finding tokens';
		} #tokenize into @tokensFound

		my @itemParents;

		push @indexMessageLog, 'tokens found: ' . scalar(@tokensFound);

		{ # second pass, look for cookie, parent, auth
			foreach my $tokenFoundRef (@tokensFound) {
				my %tokenFound = %$tokenFoundRef;

				push @indexMessageLog, 'token: ' . ($tokenFound{'token'}?$tokenFound{'token'}:'')  . '; spacer: ' . ($tokenFound{'spacer'}?$tokenFound{'spacer'}:'') . '; param = ' . ($tokenFound{'param'}?$tokenFound{'param'}:''); #todo fix bug when param or spacer is "0" #edgecase

				if ($tokenFound{'token'} && $tokenFound{'param'}) {
					if ($tokenFound{'token'} eq 'cookie') {
						if ($tokenFound{'recon'} && $tokenFound{'message'} && $tokenFound{'param'}) {
							DBAddItemAttribute($fileHash, 'cookie_id', $tokenFound{'param'}, 0, $fileHash);
							$message = str_replace($tokenFound{'recon'}, $tokenFound{'message'}, $message);
							$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
							if (!$authorKey) {
								$authorKey = $tokenFound{'param'};
								push @indexMessageLog, 'found cookie: ' . $authorKey;
							} else {
								if ($authorKey eq $tokenFound{'param'}) {
									push @indexMessageLog, 'found cookie: ' . $authorKey . ' (matches signature)';
								} else {
									push @indexMessageLog, 'found cookie: ' . $authorKey . ' (overruled by signature)';
								}
							}
						} else {
							WriteLog('IndexTextFile: warning: cookie: sanity check failed');
						}
					} # cookie

					if ($tokenFound{'token'} eq 'client') {
						if ($tokenFound{'recon'} && $tokenFound{'message'} && $tokenFound{'param'}) {
							DBAddItemAttribute($fileHash, 'client_id', $tokenFound{'param'}, 0, $fileHash);
							$message = str_replace($tokenFound{'recon'}, $tokenFound{'message'}, $message);
							$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
							if (!$authorKey) {
								$authorKey = $tokenFound{'param'};
								push @indexMessageLog, 'found client: ' . $authorKey;
							} else {
								if ($authorKey eq $tokenFound{'param'}) {
									push @indexMessageLog, 'found client: ' . $authorKey . ' (matches signature)';
								} else {
									push @indexMessageLog, 'found client: ' . $authorKey . ' (overruled by signature)';
								}
							}
						} else {
							WriteLog('IndexTextFile: warning: client: sanity check failed');
						}
					} # client

					if ($tokenFound{'token'} eq 'parent') { # >>
						if ($tokenFound{'recon'} && $tokenFound{'message'} && $tokenFound{'param'}) {
							WriteLog('IndexTextFile: DBAddItemParent(' . $fileHash . ',' . $tokenFound{'param'} . ')');
							DBAddItemParent($fileHash, $tokenFound{'param'});
							push(@itemParents, $tokenFound{'param'});

							$message = str_replace($tokenFound{'recon'}, '>>' . $tokenFound{'param'}, $message); #hacky
							# $message = str_replace($tokenFound{'recon'}, $tokenFound{'message'}, $message);

							$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
							
							push @indexMessageLog, 'found parent: ' . $tokenFound{'param'};
						} else {
							WriteLog('IndexTextFile: warning: parent: sanity check failed');
						}
					} # parent
				} #param
			} # foreach
		} # second pass, look for cookie, parent, auth

		WriteLog('IndexTextFile: %hasToken: ' . join(',', keys(%hasToken)));

		DBAddItem2($file, $fileHash, 'txt');

		push @indexMessageLog, '---';

		if ($hasToken{'example'}) {
			push @tokenMessages, 'Token #example was found, other tokens will be ignored.';
			DBAddVoteRecord($fileHash, 0, 'example');
			
			push @indexMessageLog, 'found token: #example; other tokens will be ignored.';
		} # #example
		else { # not #example
			my $itemTimestamp = $addedTime;
			if (!$itemTimestamp) {
				$itemTimestamp = DBGetItemAttribute($fileHash, 'chain_timestamp');#todo bug here, depends on chain being on
			}
			my @hashTagsAppliedToParent;

			push @indexMessageLog, 'item timestamp: ' . $itemTimestamp;

			foreach my $tokenFoundRef (@tokensFound) {
				my %tokenFound = %$tokenFoundRef;
				if ($tokenFound{'token'} && $tokenFound{'param'}) {
					WriteLog('IndexTextFile: token, param: ' . $tokenFound{'token'} . ',' . $tokenFound{'param'});

					my $targetAttribute = $tokenFound{'token'};
					if ($tokenFound{'target_attribute'}) {
						$targetAttribute = $tokenFound{'target_attribute'};
					}

					if ($tokenFound{'token'} eq $targetAttribute) {
						#todo this does not return an error if it fails
						push @indexMessageLog, 'applying: ' . $targetAttribute;
					} else {
						#todo what is this?
						push @indexMessageLog, 'applying: ' . $tokenFound{'token'} . ' (as ' . $targetAttribute . ')';
					}

					#todo put into config
					my @validTokens = qw(
						title 
						name 
						order 
						alt 
						access_log_hash
						self_timestamp
						received
						begin
						duration
						track
						host
						date
						https
						http
						boxes
						surpass
						time
						hashtag
						s_replace
					); #tokenSanityCheck

					if (in_array($tokenFound{'token'}, @validTokens)) {
						# these tokens are applied to:
						# 	if item has parent, then to the parent
						# 		otherwise: to self
						WriteLog('IndexTextFile: token_found: ' . $tokenFound{'recon'});

						push @indexMessageLog, 'valid: ' . $tokenFound{'token'};

						if (!$itemTimestamp) {
							WriteLog('IndexTextFile: warning: $itemTimestamp being set to time()');
							$itemTimestamp = GetTime(); #todo #fixme #stupid
						}
						
						if ($tokenFound{'recon'} && $tokenFound{'message'} && $tokenFound{'param'}) {
							my $newMessage = $tokenFound{'message'};
							# if ($tokenFound{'token'} eq 'http' || $tokenFound{'token'} eq 'https') {
							# 	# this hack is so that i can stay with the 3-item regex
							# 	# eventually it will probably have to be changed
							#
							# 	my $newTitle = $tokenFound{'recon'}; # set title to entire line
							# 	if (length($newTitle) > 63) {
							# 		$newTitle = substr($newTitle, 0, 60) . '...';
							# 	}
							#
							# 	#todo sanity/escape
							# 	$newMessage = '<a href="' . $tokenFound{'recon'} . '">' . $newTitle . '</a>';
							# }

							#$message = str_replace($tokenFound{'recon'}, $newMessage, $message);
							$message = str_replace($tokenFound{'recon'}, $tokenFound{'message'}, $message);

							WriteLog('IndexTextFile: %tokenFound: ' . Dumper(%tokenFound));

							if ($tokenFound{'apply_to_parent'} && @itemParents) {
								foreach my $itemParent (@itemParents) {
									DBAddItemAttribute($itemParent, $targetAttribute, $tokenFound{'param'}, $itemTimestamp, $fileHash);
								}
							} else {
								DBAddItemAttribute($fileHash, $targetAttribute, $tokenFound{'param'}, $itemTimestamp, $fileHash);

								if (
									$tokenFound{'token'} eq 'http'
									||
									$tokenFound{'token'} eq 'https'
								) {
									if (
										$tokenFound{'param'} =~ m|http://([^/]+)|
										||
										$tokenFound{'param'} =~ m|https://([^/]+)|
									) {
										my $urlDomain = $1;
										DBAddItemAttribute($fileHash, 'url_domain', $urlDomain, $itemTimestamp, $fileHash);
										
										#if (trim($tokenFound{'param'}) ne trim($message)) {
										#	my $newFileName = sha1_sum($tokenFound{'param'}) . '.txt';
										#	$newFileName = GetDir('txt') . '/' . $newFileName;
										#	PutFile($newFileName, $tokenFound{'param'});
										#}
									}
								}
							}
						} else {
							WriteLog('IndexTextFile: warning: ' . $tokenFound{'token'} . ' (generic): sanity check failed');
						}

						my $voteTime = 0;
						if ($addedTime) {
							$voteTime = $addedTime;
						}
						elsif ($itemTimestamp) {
							$voteTime = $itemTimestamp;
						}
						else {
							$voteTime = GetTime();
						}
						WriteLog('IndexTextFile: $voteTime = ' . $voteTime);

						DBAddVoteRecord($fileHash, $voteTime, $tokenFound{'token'}); #'hashtag'
					} # title, access_log_hash, http, https, alt, name, self_timestamp

					if ($tokenFound{'token'} eq 'config') { #config
						if (
							IsAdmin($authorKey) || #admin can always config #todo
							GetConfig('admin/anyone_can_config') || # anyone can config
							(GetConfig('admin/signed_can_config') || 0) || # signed can config #todo
							(GetConfig('admin/cookied_can_config') || 0) # cookied can config #todo
						) {
							my ($configKey, $configSpacer, $configValue) = ($tokenFound{'param'} =~ m/(.+)(\W)(.+)/);

							push @indexMessageLog, 'config: ' . $tokenFound{'param'};

							WriteLog('IndexTextFile: $configKey = ' . (defined($configKey) ? $configKey : '(undefined)'));
							WriteLog('IndexTextFile: $configSpacer = ' . (defined($configSpacer) ? $configSpacer : '(undefined)'));
							WriteLog('IndexTextFile: $configValue = ' . (defined($configValue) ? $configValue : '(undefined)'));

							if (!defined($configKey) || !$configKey || !defined($configValue)) {
								WriteLog('IndexTextFile: warning: $configKey or $configValue missing from $tokenFound token');
							} else {
								my $configKeyActual = $configKey;
								if ($configKey && defined($configValue) && $configValue ne '') {
									#todo merge html/clock and html/clock_format
									$configValue = trim($configValue);
								}

								if (IsAdmin($authorKey) || ConfigKeyValid($configKeyActual)) { #todo
									# admins can write to any config
									# non-admins can only write to existing config keys (and not under admin/)

									# #todo create a whitelist of safe keys non-admins can change

									DBAddConfigValue($configKeyActual, $configValue, 0, $fileHash);

									#this must be called before WriteIndexedConfig()
									#because we must flush to indexing database
									#because that's where WriteIndexedConfig() gets its new config
									IndexTextFile('flush'); #todo optimize

									#WriteIndexedConfig(); # #config/...= token in index.pl
									$message = str_replace($tokenFound{'recon'}, "[Config: $configKeyActual = $configValue]", $message);
									$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);

									if (!$titleCandidate) {
										$titleCandidate = 'Configuration change';
									}
								} else {
									# token tried to pass unacceptable config key
									$message = str_replace($tokenFound{'recon'}, "[Not Accepted: $configKeyActual]", $message);
									$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
								}
							} # sanity check
						} # has permission to config
					} # #config

					if ($tokenFound{'token'} eq 'my_name_is') { # my_name_is
						if ($tokenFound{'recon'} && $tokenFound{'message'} && $tokenFound{'param'}) {
							WriteLog('IndexTextFile: my_name_is: sanity check PASSED');
							if ($authorKey) {
								$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
								my $nameGiven = $tokenFound{'param'};
								$message =~ s/$tokenFound{'recon'}/[my name is: $nameGiven]/g;

								DBAddKeyAlias($authorKey, $tokenFound{'param'}, $fileHash); #bug here cd145d82
								DBAddKeyAlias('flush');

								if (!$titleCandidate) {
									$titleCandidate = $tokenFound{'param'} . ' has self-identified';
								}
							}
						} else {
							WriteLog('IndexTextFile: warning: my_name_is: sanity check FAILED');
						}
					} # my_name_is

					if ($tokenFound{'token'} eq 'hashtag') { #hashtag
						if ($tokenFound{'param'} eq 'remove' && GetConfig('admin/token/remove')) { #remove
							if (scalar(@itemParents)) {
								WriteLog('IndexTextFile: Found #remove token, and item has parents');
								foreach my $itemParent (@itemParents) {
									# find the author of the item in question.
									# this will help us determine whether the request can be fulfilled
									my $parentItemAuthor = DBGetItemAuthor($itemParent) || '';
									#WriteLog('IndexTextFile: #remove: IsAdmin = ' . IsAdmin($authorKey) . '; $authorKey = ' . $authorKey . '; $parentItemAuthor = ' . $parentItemAuthor);
									WriteLog('IndexTextFile: #remove: $authorKey = ' . $authorKey);
									#WriteLog('IndexTextFile: #remove: IsAdmin = ' . IsAdmin($authorKey));
									WriteLog('IndexTextFile: #remove: $parentItemAuthor = ' . $parentItemAuthor);

									# at this time only signed requests to remove are honored
									if (
										$authorKey # is signed
											&&
											(
												IsAdmin($authorKey)                   # signed by admin
													||                             # OR
												($authorKey eq $parentItemAuthor) 	   # signed by same as author
											)
									) {
										WriteLog('IndexTextFile: #remove: Found seemingly valid request to remove');

										push @indexMessageLog, 'removing item: ' . $itemParent;

										AppendFile('log/deleted.log', $itemParent);
										DBDeleteItemReferences($itemParent);

										my $htmlFilename = $HTMLDIR . '/' . GetHtmlFilename($itemParent);
										if (-e $htmlFilename) {
											WriteLog('IndexTextFile: #remove: ' . $htmlFilename . ' exists, calling unlink()');
											unlink($htmlFilename);
										}
										else {
											WriteLog('IndexTextFile: #remove: ' . $htmlFilename . ' does NOT exist, very strange');
										}

										my $itemParentPath = GetPathFromHash($itemParent);
										if (-e $itemParentPath) {
											# this only works if organize_files is on and file was put into its path
											# otherwise it will be removed at another time
											WriteLog('IndexTextFile: removing $itemParentPath = ' . $itemParentPath);
											WriteLog('IndexTextFile: unlink($itemParentPath); $itemParentPath = ' . $itemParentPath);
											#unlink($itemParentPath);
										}

										if (!GetConfig('admin/logging/record_remove_action')) {
											# log_remove remove_log
											#todo unlink the file represented by $voteFileHash, not $file (huh???)

											WriteLog('IndexTextFile: #remove: trying to remove #remove action source file');

											if (-e $file) {
												WriteLog('IndexTextFile: #remove: source file exists! ' . $file . ', calling unlink()');

												# this removes the remove call itself
												if (!trim($detokenedMessage)) {
													WriteLog('IndexTextFile: #remove: passed $detokenedMessage sanity check for ' . $file);

													DBAddTask('filesys', 'unlink', $file, time());

													#unlink($file);

													if (-e $file) {
														WriteLog('IndexTextFile: warning: just called unlink($file), but still exists: $file = ' . $file);
													}
												} else {
													WriteLog('IndexTextFile: #remove: $detokenedMessage is not FALSE, skipping file removal');
												}
											}
											else {
												WriteLog('IndexTextFile: #remove: warning: $file = ' . $file . ' does NOT exist');
											}
										}

										#todo unlink and refresh, or at least tag as needing refresh, any pages which include deleted item
									} # has permission to remove
									else {
										WriteLog('IndexTextFile: Request to remove file was not found to be valid');

										push @indexMessageLog, 'remove request declined, insufficient privileges.';
									}
								} # foreach my $itemParent (@itemParents)
							} # has parents
						} # #remove
						elsif (
							$tokenFound{'param'} eq 'admin' || #admin token needs permission
							$tokenFound{'param'} eq 'approve' ||  #approve token needs permission
							$tokenFound{'param'} eq 'person' || #person token needs permission
							$tokenFound{'param'} eq 'witness' || #witness token needs permission
							$tokenFound{'param'} eq 'vouch' || #vouch token needs permission
							$tokenFound{'param'} eq 'mavo' || #mavo token needs permission
							$tokenFound{'param'} eq 'run' || #run token needs permission
							0
						) { # permissioned token
							my $hashTag = $tokenFound{'param'};
							if (scalar(@itemParents)) {
								WriteLog('IndexTextFile: Found permissioned token ' . $tokenFound{'param'} . ', and item has parents');
								foreach my $itemParent (@itemParents) {
									# find the author of this item
									# this will help us determine whether the request can be fulfilled

									my $approveStatus = 0;
									my $approveReason = '';

									if ($authorKey) {
										if (IsAdmin($authorKey)) {
											$approveStatus = 1;
											$approveReason = 'author is admin';
										}
										elsif (
											$hashTag eq 'admin' &&
											GetConfig('admin/allow_self_admin_when_adminless') &&
											!DBGetAdminCount()
										) {
											$approveStatus = 2;
											$approveReason = 'self-admin when adminless is allowed';
										}
										elsif (
											$hashTag eq 'admin' &&
											GetConfig('admin/allow_self_admin_whenever')
										) {
											$approveStatus = 3;
											$approveReason = 'self-admin whenever is allowed';
										}
										else {
											my $publicKeyHash = DBGetAuthorPublicKeyHash($authorKey);
											my $voteTotalsRef = DBGetItemVoteTotals2($publicKeyHash);

											my %voteTotals;
											if ($voteTotalsRef) {
												%voteTotals = %{$voteTotalsRef};
											}

											WriteLog('IndexTextFile: permissioned: $publicKeyHash = ' . $publicKeyHash);
											push @indexMessageLog, 'author pubkey hash: ' . $publicKeyHash;

											if ($voteTotals{$tokenFound{'param'}}) {
												$approveStatus = 4;
												$approveReason = 'author possesses tag (4)';
											} else {
												if (GetConfig('setting/admin/allow_admin_permissions_tag_lookup_via_tagset')) { #todo

													my @authorTags = keys(%voteTotals);
													foreach my $authorTag (@authorTags) {
														my @tagset = split("\n", GetTemplate("tagset/$authorTag"));
														if (scalar(@tagset)) {
															if (in_array($tokenFound{'param'}, @tagset)) {
																$approveStatus = 5;
																$approveReason = 'found tag in tagset/' . $authorTag;
															}
														}
													}

													if (!$approveStatus) {
														$approveStatus = 0;
														$approveReason = 'found no reason to allow';
													}
												} # default/setting/admin/allow_admin_permissions_tag_lookup_via_tagset=0
											}
										}
									} # if ($authorKey)

									if ($approveStatus) {
										WriteLog('IndexTextFile: permissioned: Found seemingly valid request');
										DBAddVoteRecord($itemParent, 0, $hashTag, $authorKey, $fileHash);

										my $authorGpgFingerprint = DBGetItemAttribute($itemParent, 'gpg_fingerprint');

										if ($authorGpgFingerprint && $authorGpgFingerprint =~ m/([0-9A-F]{16})/) {
											#todo this is dirty, dirty hack
											$authorGpgFingerprint = $1;
										} else {
											$authorGpgFingerprint = '';
										}

										WriteLog('IndexTextFile: permissioned: $authorGpgFingerprint = ' . $authorGpgFingerprint);

										if ($authorGpgFingerprint) {
											WriteLog('IndexTextFile: permissioned: found $authorGpgFingerprint');
											ExpireAvatarCache($authorGpgFingerprint); #uncache
										} else {
											WriteLog('IndexTextFile: permissioned: did NOT find $authorGpgFingerprint');
										}

										DBAddVoteRecord('flush');

										DBAddPageTouch('stats', 0);

										if (!$titleCandidate) {
											$titleCandidate = '[#' . $hashTag . ']';
										}

										ExpireAvatarCache($authorKey); #uncache
										
										push @indexMessageLog, 'allowed: #' . $tokenFound{'param'} . '; reason: ' . $approveReason;

										if (GetConfig('admin/index/create_system_tags')) {
											DBAddVoteRecord($fileHash, 0, 'HasTag');
										}

										if ($hashTag eq 'run') {
											push @indexMessageLog, 'calling run on parent item';
											RunItem($itemParent);
										}
									} # $approveStatus is true
									else {
										WriteLog('IndexTextFile: Request to admin file was not found to be valid');
										$approveReason = 'lacking permissions to apply this hashtag';
										push @indexMessageLog, 'declined: #' . $tokenFound{'param'} . '; reason: ' . $approveReason;
										if (GetConfig('admin/index/create_system_tags')) {
											DBAddVoteRecord($fileHash, 0, 'HasDecline');
										}
									}
								} # foreach my $itemParent (@itemParents)
							} # has parents
						} # #admin #approve and other permissioned tags
						else { # non-permissioned hashtags
							WriteLog('IndexTextFile: non-permissioned hashtag');
							if ($tokenFound{'param'} =~ /^[0-9a-zA-Z_]+$/) { #todo actual hashtag format
								WriteLog('IndexTextFile: hashtag sanity check passed');
								my $hashTag = $tokenFound{'param'};
								if (scalar(@itemParents)) { # item has parents to apply tag to
									WriteLog('IndexTextFile: parents found, applying hashtag to them');

									foreach my $itemParentHash (@itemParents) { # apply to all parents
										WriteLog('IndexTextFile: applying hashtag, $itemParentHash = ' . $itemParentHash);
										if ($authorKey) {
											WriteLog('IndexTextFile: $authorKey = ' . $authorKey);
											# include author's key if message is signed
											DBAddVoteRecord($itemParentHash, 0, $hashTag, $authorKey, $fileHash);
										}
										else {
											WriteLog('IndexTextFile: $authorKey was FALSE');
											DBAddVoteRecord($itemParentHash, 0, $hashTag, '', $fileHash);
										}
										DBAddPageTouch('item', $itemParentHash);
										push @hashTagsAppliedToParent, $hashTag;
									} # @itemParents
								} # scalar(@itemParents)
								else {
									# no parents, self-apply
									if ($authorKey) {
										WriteLog('IndexTextFile: $authorKey = ' . $authorKey);
										# include author's key if message is signed
										DBAddVoteRecord($fileHash, 0, $hashTag, $authorKey, $fileHash);
									}
									else {
										WriteLog('IndexTextFile: $authorKey was FALSE');
										DBAddVoteRecord($fileHash, 0, $hashTag, '', $fileHash);
									}
								}
							} # valid hashtag

							if (GetConfig('admin/index/create_system_tags')) {
								DBAddVoteRecord($fileHash, 0, 'HasVote');
							}
						} # non-permissioned hashtags

						$detokenedMessage = str_replace($tokenFound{'recon'}, '', $detokenedMessage);
					} #hashtag
				} # if ($tokenFound{'token'} && $tokenFound{'param'}) {
			} # foreach @tokensFound

			if (scalar(@hashTagsAppliedToParent)) {
				if (!$titleCandidate) {
					# there's no title yet

					@hashTagsAppliedToParent = array_unique(@hashTagsAppliedToParent);

					my $titleCandidateComma = '';
					foreach my $hashTagApplied (@hashTagsAppliedToParent) {
						$titleCandidate .= ' #' . $hashTagApplied;
					}
					$titleCandidate = trim($titleCandidate);
					if (length($titleCandidate) > 25) {
						$titleCandidate = substr($titleCandidate, 0, 25) . ' [...]';
					}
					if (scalar(@itemParents) > 1) {
						$titleCandidate .= ' applied to ' . scalar(@itemParents) . ' items';
					}
				}
			} # hash tags applied to parent items
		} # not #example

		$detokenedMessage = trim($detokenedMessage);
		if (trim($detokenedMessage) eq '-- ') {
			WriteLog('IndexTextFile: warning: bandaid encountered: dashdashspace');
			#todo #bandaid
			# this should be handled by the signature_divider token
			$detokenedMessage = '';
		}

		WriteLog('IndexTextFile: $fileHash = ' . $fileHash . '; length($detokenedMessage) = ' . length($detokenedMessage));
		#WriteLog('IndexTextFile: $fileHash = ' . $fileHash . '; $detokenedMessage = "' . $detokenedMessage . '"');

		
#		if ($fileHash eq 'ef5f020ffae013876493cf25e323a2c67a3f09db') {
#			die($detokenedMessage);
#		}

		if ($detokenedMessage eq '') {
			# add #NoText label/tag
			WriteLog('IndexTextFile: no $detokenedMessage, setting #NoText; $fileHash = ' . $fileHash);
			if (GetConfig('admin/index/create_system_tags')) {
				DBAddVoteRecord($fileHash, 0, 'NoText');
			}
			#DBAddItemAttribute($fileHash, 'all_tokens_no_text', 1);

			if ($titleCandidate) {
				#no message, only tokens. try to get a title from the tokens, which we stashed earlier
				DBAddItemAttribute($fileHash, 'title', $titleCandidate);
			}
		}
		else { # has $detokenedMessage
			WriteLog('IndexTextFile: has $detokenedMessage $fileHash = ' . $fileHash);
			{ #title:
				my $firstEol = index($detokenedMessage, "\n");
				my $titleLength = GetConfig('admin/index/title_length'); #default = 63
				if (!$titleLength) {
					$titleLength = 255;
					WriteLog('#todo: warning: $titleLength was false');
				}
				if ($firstEol == -1) {
					if (length($detokenedMessage) > 1) {
						$firstEol = length($detokenedMessage);
					}
				}
				if ($firstEol > $titleLength) {
					$firstEol = $titleLength;
				}
				if ($firstEol > 0) {
					my $title = '';
					if ($firstEol <= $titleLength) {
						$title = substr($detokenedMessage, 0, $firstEol);
					} else {
						$title = substr($detokenedMessage, 0, $titleLength) . '...';
					}
					DBAddItemAttribute($fileHash, 'title', $title, 0);

					if (GetConfig('admin/index/create_system_tags')) {
						#DBAddVoteRecord($fileHash, 0, GetString('HasTitle'));
						#DBAddVoteRecord($fileHash, 0, GetString('HasTitle'));
						DBAddVoteRecord($fileHash, 0, 'HasTitle');
					}
				}
			}

			if (GetConfig('admin/index/create_system_tags')) {
				DBAddVoteRecord($fileHash, 0, 'HasText');
			}
			#DBAddPageTouch('tag', 'HasText');

			my $messageHash = GetFileMessageHash($file);
			#my $normalizedHash = sha1_hex(trim($detokenedMessage));
			#v1
			#
			# {#v2
			# 	my $hash = sha1_hex('');
			# 	#draft better normalized hash
			# 	my @lines = split("\n", $detokenedMessage);
			# 	my @lines2;
			# 	for my $line (@lines) {
			# 		$line = trim($line);
			# 		if ($line ne '') {
			# 			push @lines2, lc($line);
			# 		}
			# 	}
			# 	my @lines3 = uniq(sort(@lines2));
			# 	for my $line (@lines3) {
			# 		$hash = sha1_hex($hash . $line);
			# 	}
			# 	$normalizedHash = $hash;
			# }

			if (GetConfig('setting/admin/index/extra_hashes')) {
				DBAddItemAttribute($fileHash, 'message_hash', $messageHash, 0);
				#	DBAddItemAttribute($fileHash, 'normalized_hash', $normalizedHash, 0);
			}

			#todo reparent item if another with the same normhash already exists
		} # has a $detokenedMessage

		if ($message) { # side effect: message cannot be 0
			#if ($message || (defined($message) && $message == 0)) {
			# cache the processed message text
			my $messageCacheName = GetMessageCacheName($fileHash);
			WriteLog('IndexTextFile: Calling PutFile(), $fileHash = ' . $fileHash . '; $messageCacheName = ' . $messageCacheName);
			PutFile($messageCacheName, $message);
		} else {
			WriteLog('IndexTextFile: warning: I was going to save $messageCacheName, but $message is blank! $file = ' . $file);
			WriteLog('IndexTextFile: warning: I was going to save $messageCacheName, but $message is blank! $fileHash = ' . $fileHash);
			return ''; # $message is FALSE sanity check
		}
	} # .txt

	if (scalar(@indexMessageLog)) {
		my $indexLog = join("\n", @indexMessageLog);
		PutCache('index_log/' . $fileHash, $indexLog); # parse_log parse.log ParseLog
	}

	if (GetConfig('admin/index/expire_html_when_indexing')) {
		#uncache
		if ($authorKey) {
			RemoveHtmlFile('author/' . $authorKey . '/index.html');
		}
		require_once('expire_pages.pl');
		ExpirePages($fileHash);
	}

	return $fileHash; # we did it!
} # IndexTextFile()

1;
