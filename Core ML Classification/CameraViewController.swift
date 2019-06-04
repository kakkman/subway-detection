/**
 * Copyright IBM Corporation 2017, 2018
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import UIKit
import AVFoundation
import Vision

class CameraViewController: UIViewController {

    // MARK: - IBOutlets
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var outlineView: UIImageView!
    @IBOutlet weak var focusView: UIImageView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    
    // MARK: - Variable Declarations
    
    let coreMLModel = Model().model
    
    let photoOutput = AVCapturePhotoOutput()
    lazy var captureSession: AVCaptureSession? = {
        guard let backCamera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: backCamera) else {
                return nil
        }
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        captureSession.addInput(input)
       // setContentMode:UIViewContentModeScaleAspectFill
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = CGRect(x: view.bounds.minX, y: view.bounds.minY, width: view.bounds.width, height: view.bounds.height)
            previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            previewLayer.connection?.videoOrientation = .portrait
            cameraView.layer.addSublayer(previewLayer)
            return captureSession
        }
        return nil
    }()
    
    var editedImage = UIImage()
    var originalConfs = [VNClassificationObservation]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        captureSession?.startRunning()
        focusView.isHidden = false
        resetUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let drawer = pulleyViewController?.drawerContentViewController as? ResultsTableViewController else {
            return
        }
        drawer.delegate = self
    }
    
    // MARK: - Image Classification
    
    func classifyImage(_ image: UIImage, localThreshold: Double = 0.0) {
        print("start classifyImage")

        guard let croppedImage = cropToCenter(image: image, targetSize: CGSize(width: 224, height: 224)) else {
            return
        }
        
        editedImage = croppedImage
        
        showResultsUI(for: image)
        
        guard let cgImage = editedImage.cgImage else {
            return
        }
        
        CoreMLUtils.classify(cgImage, for: coreMLModel) { classifications, error in
            // Make sure that an image was successfully classified.
            guard let classifications = classifications else {
                return
            }
            
            DispatchQueue.main.async {
                self.push(results: classifications)
            }
            
            self.originalConfs = classifications
        }
    }
    
    func cropToCenter(image: UIImage, targetSize: CGSize) -> UIImage? {
        print("start cropToCenter")
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        let offset = abs(CGFloat(cgImage.width - cgImage.height) / 2)
        let newSize = CGFloat(min(cgImage.width, cgImage.height))
        
        let cropRect: CGRect
        if cgImage.width < cgImage.height {
            cropRect = CGRect(x: 0.0, y: offset, width: newSize, height: newSize)
        } else {
            cropRect = CGRect(x: offset, y: 0.0, width: newSize, height: newSize)
        }
        
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        let image = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        let resizeRect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: resizeRect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    func dismissResults() {
        print("start dismissResults")
        push(results: [], position: .closed)
    }
    
    func push(results: [VNClassificationObservation], position: PulleyPosition = .partiallyRevealed) {
        print("start push")
        guard let drawer = pulleyViewController?.drawerContentViewController as? ResultsTableViewController else {
            return
        }
        drawer.classifications = results
        pulleyViewController?.setDrawerPosition(position: position, animated: true)
        drawer.tableView.reloadData()
    }
    
    func showResultsUI(for image: UIImage) {
        print("start showResultsUI")
        imageView.image = image
        imageView.isHidden = false
        closeButton.isHidden = false
        captureButton.isHidden = true
        focusView.isHidden = true
    }
    
    func resetUI() {
        print("start resetUI")
        if captureSession != nil {
            imageView.isHidden = true
            captureButton.isHidden = false
            focusView.isHidden = false
        } else {
            imageView.image = UIImage(named: "Background")
            imageView.isHidden = false
            captureButton.isHidden = true
            focusView.isHidden = true
        }
        outlineView.isHidden = true
        closeButton.isHidden = true
        focusView.isHidden = false
        dismissResults()
    }
    
    // MARK: - IBActions
    
    @IBAction func capturePhoto() {
        print("start capturePhoto")
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    @IBAction func reset() {
        resetUI()
    }
}

// MARK: - Error Handling

extension CameraViewController {
    func showAlert(_ alertTitle: String, alertMessage: String) {
        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        guard let photoData = photo.fileDataRepresentation(),
            let image = UIImage(data: photoData) else {
            return
        }
        
        classifyImage(image)
    }
}
// MARK: - TableViewControllerSelectionDelegate

extension CameraViewController: TableViewControllerSelectionDelegate {
    func didSelectItem(_ name: String) {
    }
}
