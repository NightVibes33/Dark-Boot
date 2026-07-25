            CGContextSetStrokeColorWithColor(ctx, G2RGB(0.8, 0.2 + 0.7 * phase, 1.0, 1.0-phase*0.55).CGColor);
            CGContextSetLineWidth(ctx, 4.0);
            CGContextStrokeRect(ctx, CGRectMake(c.x-side/2.0, c.y-side/2.0, side, side));
        }
    } else if ([style isEqualToString:@"spark"]) {
        for (NSUInteger ray = 0; ray < 18; ray++) {
            CGFloat angle = ray / 18.0 * M_PI * 2.0 + t * M_PI * 2.0;
