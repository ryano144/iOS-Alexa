//
//  AVSUploader.swift
//  AVSExample
//

import Foundation

struct PartData {
    var headers: [String:String]
    var data: Data
}

class AVSUploader: NSObject, URLSessionTaskDelegate {
    
    var authToken:String?
    var jsonData:String?
    var audioData:Data?
    
    var errorHandler: ((_ error:NSError) -> Void)?
    var progressHandler: ((_ progress:Double) -> Void)?
    var successHandler: ((_ data:Data, _ parts:[PartData]) -> Void)?
    
    fileprivate var session: Foundation.URLSession!
    
    func start() throws {
        if self.authToken == nil || self.jsonData == nil || self.audioData == nil {
            throw NSError(domain: Config.Error.ErrorDomain, code: Config.Error.AVSUploaderSetupIncompleteErrorCode, userInfo: [NSLocalizedDescriptionKey : "AVS upload options not set"])
        }
        
        if self.session == nil {
            self.session = Foundation.URLSession(configuration: Foundation.URLSession.shared.configuration, delegate: self, delegateQueue: nil)
        }
        
        self.postRecording(self.authToken!, jsonData: self.jsonData!, audioData: self.audioData!)
    }
    
    fileprivate func parseResponse(_ data:Data, boundry:String) -> [PartData] {
        
        let innerBoundry = "\(boundry)\r\n".data(using: String.Encoding.utf8)!
        let endBoundry = "\r\n\(boundry)--\r\n".data(using: String.Encoding.utf8)!
        
        var innerRanges = [Range<Data.Index>]()
        var lastStartingLocation = 0
        
        var boundryRange = data.range(of: innerBoundry, options: Data.SearchOptions(), in: (lastStartingLocation ..< lastStartingLocation+data.count))
        while(boundryRange != nil) {
            
            lastStartingLocation = boundryRange!.upperBound
            boundryRange = data.range(of: innerBoundry, options: Data.SearchOptions(), in: (lastStartingLocation ..< data.count))
            
            if boundryRange != nil {
                innerRanges.append((lastStartingLocation ..< lastStartingLocation + boundryRange!.lowerBound - innerBoundry.count))
            } else {
                innerRanges.append(lastStartingLocation ..< data.count)
            }
        }
        
        var partData = [PartData]()
        
        for innerRange in innerRanges {
            let innerData = data.subdata(in: innerRange)
            
            let headerRange = innerData.range(of: "\r\n\r\n".data(using: String.Encoding.utf8)!, options: Data.SearchOptions(), in: (0 ..< innerRange.count))
            
            var headers = [String:String]()
            if let headerData = NSString(data: innerData.subdata(in: (0 ..< (headerRange?.lowerBound)!)), encoding: String.Encoding.utf8.rawValue) as String? {
                let headerLines = headerData.characters.split{$0 == "\r\n"}.map{String($0)}
                for headerLine in headerLines {
                    let headerSplit = headerLine.characters.split{ $0 == ":" }.map{String($0)}
                    headers[headerSplit[0]] = headerSplit[1].trimmingCharacters(in: CharacterSet.whitespaces)
                }
            }
            
            let startLocation = headerRange?.upperBound
            let contentData = innerData.subdata(in: (startLocation! ..< innerRange.count))
            
            let endContentRange = contentData.range(of: endBoundry, options: NSData.SearchOptions(), in: (0 ..< contentData.count))
            if endContentRange != nil {
                partData.append(PartData(headers: headers, data: contentData.subdata(in: (0 ..< (endContentRange?.lowerBound)!))))
            } else {
                partData.append(PartData(headers: headers, data: contentData))
            }
        }
        
        return partData
    }
    
    fileprivate func postRecording(_ authToken:String, jsonData:String, audioData:Data) {
        let request = NSMutableURLRequest(url: URL(string: "https://access-alexa-na.amazon.com/v1/avs/speechrecognizer/recognize")!)
        request.cachePolicy = NSURLRequest.CachePolicy.reloadIgnoringCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let boundry = UUID().uuidString
        let contentType = "multipart/form-data; boundary=\(boundry)"
        
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        let bodyData = NSMutableData()
        
        bodyData.append("--\(boundry)\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append(jsonData.data(using: String.Encoding.utf8)!)
        bodyData.append("\r\n".data(using: String.Encoding.utf8)!)
        
        bodyData.append("--\(boundry)\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append("Content-Disposition: form-data; name=\"audio\"\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append("Content-Type: audio/L16; rate=16000; channels=1\r\n\r\n".data(using: String.Encoding.utf8)!)
        bodyData.append(audioData)
        bodyData.append("\r\n".data(using: String.Encoding.utf8)!)
        
        bodyData.append("--\(boundry)--\r\n".data(using: String.Encoding.utf8)!)
        
        let uploadTask = self.session.uploadTask(with: request as URLRequest, from: bodyData as Data, completionHandler: { (data:Data?, response:URLResponse?, error:Error?) -> Void in
            
            self.progressHandler?(100.0)
            
            if let e = error {
                self.errorHandler?(e as NSError)
            } else {
                if let httpResponse = response as? HTTPURLResponse {
                    
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299 {
                        if let responseData = data, let contentTypeHeader = httpResponse.allHeaderFields["Content-Type"] {
                            var boundry: String?
                            let ctbRange = (contentTypeHeader as AnyObject).range(of: "boundary=.*?;", options: .regularExpression)
                            if ctbRange.location != NSNotFound {
                                let boundryNSS = (contentTypeHeader as AnyObject).substring(with: ctbRange) as NSString
                                boundry = boundryNSS.substring(with: NSRange(location: 9, length: boundryNSS.length - 10))
                            }
                            
                            if let b = boundry {
                                self.successHandler?(responseData, self.parseResponse(responseData, boundry: b))
                            } else {
                                self.errorHandler?(NSError(domain: Config.Error.ErrorDomain, code: Config.Error.AVSResponseBorderParseErrorCode, userInfo: [NSLocalizedDescriptionKey : "Could not find boundry in AVS response"]))
                            }
                        }
                    } else {
                        var message: NSString?
                        if data != nil {
                            do {
                                if let errorDictionary = try JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: 0)) as? [String:AnyObject], let errorValue = errorDictionary["error"] as? [String:String], let errorMessage = errorValue["message"] {
                                    
                                    message = errorMessage as NSString
                                    
                                } else {
                                    message = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                                }
                            } catch {
                                message = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                            }
                        }
                        let finalMessage = message == nil ? "" : message!
                        self.errorHandler?(NSError(domain: Config.Error.ErrorDomain, code: Config.Error.AVSAPICallErrorCode, userInfo: [NSLocalizedDescriptionKey : "AVS error: \(httpResponse.statusCode) - \(finalMessage)"]))
                    }
                    
                }
            }
        } as (Data?, URLResponse?, Error?) -> Void)
        
        uploadTask.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        
        self.progressHandler?(Double(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) * 100.0)
        
    }
}
