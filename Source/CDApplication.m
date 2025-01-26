// CDApp.m
// cocoadialog
//
// Copyright (c) 2004-2017 Mark A. Stratman <mark@sporkstorms.org>, Mark Carver <mark.carver@me.com>.
// All rights reserved.
// Licensed under GPL-2.

#import "CDApplication.h"

// Controls.
#import "CDCheckbox.h"
#import "CDFileSelect.h"
#import "CDFileSave.h"
#import "CDInputbox.h"
#import "CDDropdown.h"
#import "CDProgressbar.h"
#import "CDRadio.h"
#import "CDSlider.h"
#import "CDTextbox.h"
#import "CDUsage.h"

@implementation CDApplication

#pragma mark - Properties
- (NSString *) baseUrl {
    return @"https://cocoadialog.com";
}

- (NSString *) name {
    NSBundle *b =[NSBundle mainBundle];
    return b.infoDictionary[@"CFBundleName"];
}

- (NSString *) templateDataKey {
    return @"app";
}

- (NSDictionary *) templateDataValue {
    return @{
             @"currentYear": [NSNumber numberWithInteger:[[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:[NSDate date]]],
             @"name": self.name,
             @"title": self.title,
             @"url": @{
                     @"homepage": self.baseUrl,
                     @"documentation": self.baseUrl.append(@"/docs"),
                     @"cli": @"https://en.wikipedia.org/wiki/Command-line_interface",
                     },
             @"version": self.version,
             };
}

- (NSString *) title {
    return [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"]?: self.name;
}

- (NSString *) version {
    return [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];
}

#pragma mark - Public static methods
+ (NSArray<NSString *> *) availableControls {
    return @[
             // Dialogs.
             @"checkbox",
             @"dropdown",
             @"input",
             @"msgbox",
             @"radio",
             @"progressbar",
             @"slider",
             @"textbox",

             // File.
             @"open",
             @"save",
             ].sortedAlphabetically;
}

+ (NSDictionary<NSString *,NSString *> *) deprecatedControls {
    return @{
             @"fileselect":                     @"open",
             @"filesave":                       @"save",
             @"inputbox":                       @"input",
             @"ok-msgbox":                      @"ok-cancel",
             @"secure-inputbox":                @"secure-input",
             @"secure-standard-inputbox":       @"secure-standard-input",
             @"standard-inputbox":              @"standard-input",
             @"yesno-msgbox":                   @"question",
             };
}

+ (NSDictionary<NSString *,NSString *> *) removedControls {
    return @{
             @"bubble": @"https://github.com/julienXX/terminal-notifier",
             @"notify": @"https://github.com/julienXX/terminal-notifier",
             };
}

#pragma mark - Public instance methods
- (void) applicationDidFinishLaunching:(NSNotification *)notification {
    // Immediately exit if we're testing.
    if (self.isTesting) {
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        [NSApp run];
        exit(0);
    }
        
    // Instantiate shared instances before anything else.
    _terminal = [CDTerminal sharedInstance];

    // Retrieve the control name and class based on terminal arguments.
    NSString *controlName = [self controlName];
    Class controlClass = [self controlClassForName:controlName];

    // Retrieve all the available options for the control and process the terminal arguments.
    _options = [controlClass availableOptions].processTerminalArguments();

    // Show a warning if the control was deprecated.
    if (deprecatedFrom && deprecatedTo) {
        self.terminal.warning(@"The %@ control has been deprecated and will be removed in a future release. Please use the %@ control instead.", deprecatedFrom.doubleQuote.white, deprecatedTo.doubleQuote.white, nil);
    }

    // Immediately fatal if the control was removed.
    if (removedControl && removedReplacement) {
        self.terminal.error(@"The %@ control has been removed. Please use %@ instead.", removedControl.doubleQuote.white, removedReplacement.white, nil).exit(CDTerminalExitCodeControlUnknown);
    }

    // Indicate that this is a control alias.
    if (self.controlAlias) {
        self.terminal.verbose(@"Control alias: %@ => %@", self.controlAlias.name.doubleQuote, self.controlAlias.controlName.doubleQuote, nil);
    }

    // If a control class was provided, use it to contruct the control.
    _control = [(CDControl *)[controlClass alloc] initWithName:controlName alias:_controlAlias];

    // Show usage.
    if ([controlName isEqualToStringCaseInsensitive:@"help"] || _options[@"help"].wasProvided) {
        [[CDUsage usage] showUsage];
        exit(0);
    }
    // Show version.
    else if ([controlName isEqualToStringCaseInsensitive:@"version"] || _options[@"version"].wasProvided) {
        [self.terminal writeLine:self.version];
        exit(0);
    }
    // Unknown control.
    else if (_control.isBaseControl && controlName != nil) {
        self.terminal.error(@"Unknown control: %@\n", controlName.doubleQuote, nil).exit(CDTerminalExitCodeControlUnknown);
    }

    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

    self.terminal.verbose(@"Initiating control: %@", self.control.name.doubleQuote, nil);

    // Warn about deprecated options.
    for (NSString *name in self.control.options.deprecatedOptions) {
        CDOption *deprecated = self.control.options.deprecatedOptions[name];
        if (deprecated.wasProvided) {
            self.terminal.warning(@"The %@ option has been deprecated. Please use the %@ option instead.", deprecated.name.optionFormat, deprecated.deprecatedTo.optionFormat, nil);
        }
    }

    // Warn about unknown options.
    NSArray *unknown = [self.control.options unknownOptions].sortedAlphabetically;
    if (unknown.count) {
        for (NSString *name in unknown) {
            self.terminal.warning(NSLocalizedString(@"WARNING_UNKNOWN_OPTION".localized, nil), name.optionFormat, nil);
        }
    }

    // Warn if multiple value options don't specify argument breaks.
    for (NSString *name in self.control.options.missingArgumentBreaks) {
        self.terminal.warning(NSLocalizedString(@"WARNING_MISSING_ARGUMENT_BREAK".localized, nil), name.optionFormat, nil);
    }

    // Validate minimum and maximum values were provided.
    for (NSString *name in self.control.options) {
        CDOption *option = self.control.options[name];
        if (option.wasProvided) {
            if (option.values.filterEmpty.count < option.minimumValues.unsignedIntegerValue) {
                self.terminal.error(@"The %@ control requires a minimum of %@ values for the %@ option.", self.control.name.doubleQuote, option.minimumValues, name.optionFormat, nil).exit(CDTerminalExitCodeOptionInvalid);
            }
            if (option.maximumValues.unsignedIntegerValue && option.values.filterEmpty.count > option.maximumValues.unsignedIntegerValue) {
                self.terminal.error(@"The %@ control is limited to a maximum of %@ values for the %@ option.", self.control.name.doubleQuote, option.maximumValues, name.optionFormat, nil).exit(CDTerminalExitCodeOptionInvalid);
            }
        }
    }

    // Validate control option requirements.
    NSMutableArray *missingOptions = [NSMutableArray array];
    NSDictionary *required = self.control.options.requiredOptions;
    if (required.count) {
        for (NSString *name in required) {
            if (!self.control.options[name].wasProvided) {
                [missingOptions addObject:name];
            }
        }
    }
    if (missingOptions.count) {
        NSString *missing = [[missingOptions.sortedAlphabetically prependStringsWith:@"--"] componentsJoinedByString:@", "];
        self.terminal.error(@"The %@ control requires the following options: %@", self.control.name.doubleQuote, missing, nil).exit(CDTerminalExitCodeOptionRequired);
    }

    // Create the control.
    [self.control createControl];

    // Bring application into focus.
    // Because this application isn't going to be double-clicked, or
    // launched with the "open" command-line tool, it won't necessarily
    // come to the front automatically.
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

    // Run the control.
    // The control is now responsible for terminating cocoadialog,
    // which should be invoked by calling the method [self stopControl]
    // from the control's action method(s).
    [self.control runControl];
}

- (NSArray <CDControlAlias *> *)controlAliases {
    NSString *standardButtonString = @"--buttons Okay Cancel";
    CDControlAliasProcessBlock okayButton = ^(CDControl *control) {
        control.options[@"buttons"].provided(YES);
        NSArray <NSString *> *values = control.options[@"buttons"].arrayValue;
        if (values.count < 1 || (values.count >= 1 && values[0].isBlank)) {
            [control.options[@"buttons"] setValue:@"Okay" atIndex:0];
        }
    };
    CDControlAliasProcessBlock cancelButton = ^(CDControl *control) {
        control.options[@"buttons"].provided(YES);
        NSArray <NSString *> *values = control.options[@"buttons"].arrayValue;
        if (values.count < 2 || (values.count >= 2 && values[1].isBlank)) {
            [control.options[@"buttons"] setValue:@"Cancel" atIndex:1];
        }
    };
    CDControlAliasProcessBlock standardButtons = ^(CDControl *control) {
        okayButton(control);
        cancelButton(control);
    };
    return @[
             CDControlAlias.create(@"about", @"textbox").usage(@"Displays the about dialog and contains acknowledgements.").process(^(CDControl *control) {
                 // Ignore user provided options.
                 for (NSString* name in control.options) {
                     control.options[name].provided(NO);
                 }

                 // Explicitly set options to create the "About" dialog.
                 control.options[@"icon"].provided(YES).rawValue(self.name);
                 control.options[@"icon-size"].provided(YES).rawValue(@"96");
                 control.options[@"header"].provided(YES).rawValue([NSString stringWithFormat:@"# %@", self.title]);
                 control.options[@"width"].provided(YES).rawValue(@"550");
                 control.options[@"buttons"].provided(YES).rawValue(@"Okay");
                 control.options[@"markdown"].provided(YES).rawValue(@"YES");
                 control.options[@"message"].provided(YES).rawValue(control.template.render(@"About", self));
                 control.options[@"file"].provided(YES).rawValue([[NSBundle mainBundle] pathForResource:@"Acknowledgements" ofType:@"md"]);
             }),
             CDControlAlias.create(@"ok", @"msgbox").usage(@"--buttons Okay").process(okayButton),
             CDControlAlias.create(@"ok-cancel", @"msgbox").usage(standardButtonString).process(standardButtons),
             CDControlAlias.create(@"secure-input", @"input").usage(@"--secure").process(^(CDControl *control) {
                 control.options[@"secure"].provided(YES).rawValue(@"YES");
             }),
             CDControlAlias.create(@"secure-standard-input", @"input").usage(@"--secure ".append(standardButtonString)).process(^(CDControl *control) {
                 control.options[@"secure"].provided(YES).rawValue(@"YES");
                 standardButtons(control);
             }),
             CDControlAlias.create(@"standard-dropdown", @"dropdown").usage(standardButtonString).process(standardButtons),
             CDControlAlias.create(@"standard-input", @"input").usage(standardButtonString).process(standardButtons),
             CDControlAlias.create(@"question", @"msgbox").usage(@"--buttons Yes No Cancel").process(^(CDControl *control) {
                 control.options[@"buttons"].wasProvided = YES;
                 NSArray <NSString *> *values = control.options[@"buttons"].arrayValue;
                 if (values.count < 1 || (values.count >= 1 && values[0].isBlank)) {
                     [control.options[@"buttons"] setValue:@"Yes" atIndex:0];
                 }
                 if (values.count < 2 || (values.count >= 2 && values[1].isBlank)) {
                     [control.options[@"buttons"] setValue:@"No" atIndex:1];
                 }
                 if (control.options[@"no-cancel"].boolValue) {
                     if (!control.options[@"cancel-button"].wasProvided) {
                         control.options[@"cancel-button"].setDefaultValue(@"No");
                     }
                 }
                 else {
                     if (values.count < 3 || (values.count >= 3 && values[2].isBlank)) {
                         [control.options[@"buttons"] setValue:@"Cancel" atIndex:2];
                     }
                 }
             }),
             ];
}

- (NSDictionary *) controlClasses {
    return @{
             @"checkbox": [CDCheckbox class],
             @"dropdown": [CDDropdown class],
             @"open": [CDFileSelect class],
             @"save": [CDFileSave class],
             @"input": [CDInputbox class],
             @"msgbox": [CDDialog class],
             @"progressbar": [CDProgressbar class],
             @"radio": [CDRadio class],
             @"slider": [CDSlider class],
             @"textbox": [CDTextbox class],

             // @todo Add back the notify control class if support is ever added back in.
             // @see https://github.com/cocoadialog/cocoadialog/issues/92
             // @"notify": [CDNotifyControl class],
             };
}


- (Class) controlClassForName:(NSString *)controlName {
    Class controlClass;
    if (controlName) {
        controlClass = [self.controlClasses objectForKey:controlName.lowercaseString];
    }
    return controlClass ?: [CDControl class];
}

- (NSString *) controlName {
    NSString *controlName = nil;
    NSMutableArray <NSString*>* args = self.terminal.arguments;
    NSArray *controls = [CDApplication availableControls];

    // Attempt to find an exact match with a currently supported control.
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([controls containsObject:args[i]]) {
            controlName = args[i];
        }
    }

    // Dynamically replace deprecated control name with a supported control name.
    NSDictionary *deprecatedControls = [CDApplication deprecatedControls];
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *replacement = [deprecatedControls objectForKey:args[i].lowercaseString];
        if (replacement != nil) {
            deprecatedFrom = args[i].lowercaseString;
            deprecatedTo = replacement;
            controlName = replacement;
            [args replaceObjectAtIndex:i withObject:controlName];
            break;
        }
    }

    // Detect if a control was removed.
    NSDictionary *removedControls = [CDApplication removedControls];
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *removed = args[i].lowercaseString;
        NSString *replacement = [removedControls objectForKey:removed];
        if (replacement != nil) {
            removedControl = removed;
            removedReplacement = replacement;
            break;
        }
    }

    // No explicit control name was found.
    if (!controlName) {
        NSString *firstArg;
        for (NSString* arg in args) {
            if (![CDOptions isOption:arg]) {
                firstArg = arg;
            }
            break;
        }

        // Attempt to just use the first argument that was passed.
        if (firstArg) {
            controlName = firstArg;
        }
        // Or show usage if executed from a CLI.
        else if (self.terminal.isCLI) {
            controlName = @"help";
        }
        // Or show the about dialog if executed from the GUI.
        else {
            controlName = @"about";
        }
    }

    // See if control name is an alias and replace it with the proper control name.
    if (controlName && !removedControl) {
        _controlAlias = [self getControlAliasFor:controlName];
        if (_controlAlias) {
            controlName = _controlAlias.controlName;
        }
    }

    return controlName;
}

- (CDControlAlias *)getControlAliasFor:(NSString *)name {
    NSArray *controlAliases = self.controlAliases;
    for (CDControlAlias *alias in controlAliases) {
        if ([alias.name isEqualToStringCaseInsensitive:name]) {
            return alias;
        }
    }
    return nil;
}

// Returns YES if we are currently being unittested.
- (BOOL) isTesting {
    BOOL answer = NO;
    Class testProbeClass;
    testProbeClass = NSClassFromString(@"XCTestProbe");
    if (testProbeClass) {
        answer = YES;
    }
    return answer;
}

@end
