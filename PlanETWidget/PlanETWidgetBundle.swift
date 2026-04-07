//
//  PlanETWidgetBundle.swift
//  PlanETWidget
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import WidgetKit
import SwiftUI

// @main
struct PlanETWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlanETWidget()
        PlanETWidgetControl()
        PlanETWidgetLiveActivity()
    }
}
