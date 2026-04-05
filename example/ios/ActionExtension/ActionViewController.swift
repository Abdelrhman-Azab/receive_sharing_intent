//
//  ActionViewController.swift
//  ActionExtension
//
//  Created by Kasem Mohamed on 2024-02-05.
//  Copyright © 2024 The Chromium Authors. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

class ActionViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        var imageFound = false
        guard let extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            return
        }

        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    weak var weakImageView = self.imageView
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil, completionHandler: { (imageURL, error) in
                        OperationQueue.main.addOperation {
                            if let strongImageView = weakImageView {
                                if let imageURL = imageURL as? URL {
                                    if let imageData = try? Data(contentsOf: imageURL) {
                                        strongImageView.image = UIImage(data: imageData)
                                    }
                                }
                            }
                        }
                    })
                    
                    imageFound = true
                    break
                }
            }
            
            if (imageFound) {
                break
            }
        }
    }

    @IBAction func done() {
        guard let extensionContext else {
            return
        }
        extensionContext.completeRequest(returningItems: extensionContext.inputItems, completionHandler: nil)
    }

}
