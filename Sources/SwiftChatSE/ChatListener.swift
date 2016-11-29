//
//  ChatListener.swift
//  FireAlarm
//
//  Created by NobodyNada on 8/28/16.
//  Copyright © 2016 NobodyNada. All rights reserved.
//

import Foundation
import Dispatch

open class ChatListener {
	open let room: ChatRoom
	
	open let commands: [Command.Type]
	
	open var info: Any? = nil
	
	///The name of the bot.  A message must start with this name to be recognized as a command.
	open var name = "@FireAlarm"
	
	///The number of characters of the name that must be included.
	///
	///
	///For example, if `name` is `@FireAlarm` and `minNameCharacters` is 4,
	///`@FireAlarm`, `@Fire`, and `@Fir` will all be recognized, but
	///`@FirTree`, `@Fi`, and `@Kyll` will not.
	open var minNameCharacters = 4
	
	open var shutdownHandler: (Bool, Bool) -> () = {shouldReboot, isUpdate in}
	
	open func onShutdown(_ handler: @escaping (Bool, Bool) -> ()) {
		shutdownHandler = handler
	}
	
	let commandQueue = DispatchQueue(label: "Command Queue", attributes: DispatchQueue.Attributes.concurrent)
	
	var runningCommands = [Command]()
	
	public enum StopAction {
		case run
		case halt
		case reboot
		case update
	}
	
	fileprivate var pendingStopAction = StopAction.run
	
	fileprivate func runCommand(_ command: Command) {
		let required = type(of: command).privileges()
		let missing = command.message.user.missing(from: required)
		
		
		guard missing.isEmpty else {
			let message = "You need the \(formatArray(missing.names, conjunction: "and")) " +
			"\(pluralize(missing.names.count, "privilege")) to run that command."
			
			room.postReply(message, to: command.message)
			return
		}
		
		
		
		runningCommands.append(command)
		commandQueue.async {
			do {
				try command.run()
			}
			catch {
				handleError(error, "while running \"\(command.message.content)\"")
			}
			self.runningCommands.remove(at: self.runningCommands.index {$0 === command}!)
			if (self.pendingStopAction != .run) && self.runningCommands.isEmpty {
				self.shutdownHandler(self.pendingStopAction == .reboot, self.pendingStopAction == .update)
			}
		}
	}
	
	fileprivate func handleCommand(_ message: ChatMessage) {
		var components = message.content.lowercased().components(separatedBy: CharacterSet.whitespaces)
		components.removeFirst()
		
		var args = [String]()
		
		var commandScores = [String:Int]()
		
		for command in commands {
			let usages = command.usage()
			
			for i in 0..<usages.count {
				var score = 0
				let usage = usages[i]
				args = []
				
				var match = true
				let usageComponents = usage.components(separatedBy: CharacterSet.whitespaces)
				let lastIndex = min(components.count, usageComponents.count)
				
				for i in 0..<lastIndex {
					let component = components[i]
					let usageComponent = usageComponents[i]
					
					if usageComponent == "*" {
						args.append(component)
					}
					else if usageComponent == "..." {
						//everything else is arguments; add them to the list
						args.append(contentsOf: components[i..<components.count])
					}
					else if component != usageComponent {
						match = false
					}
				}
				
				
				let minCount = usageComponents.last! == "..." ? usageComponents.count - 1 : usageComponents.count
				if components.count < minCount {
					match = false
				}
				
				
				if match {
					runCommand(command.init(listener: self, message: message, arguments: args, usageIndex: i))
					return
				}
				else {
					//Determine how similar the input was to this command.
					//Higher score means more differences.
					var availableComponents = components	//The components which have not been "used."
					//Each component may only be matched once.
					var availableUsageComponents = usageComponents.filter {
						$0 != "*" && $0 != "..."
					}
					
					//While there are unused components, iterate over all available components and remove the closest pairs.
					
					while !availableComponents.isEmpty && !availableUsageComponents.isEmpty {
						var bestMatch: (score: Int, component: String, usageComponent: String)?
						
						for usageComponent in availableUsageComponents {
							if usageComponent == "*" || usageComponent == "..." {
								continue
							}
							
							for component in availableComponents {
								let distance = Levenshtein.distanceBetween(usageComponent, and: component)
								let componentScore = min(distance, usageComponent.characters.count)
								
								if componentScore < bestMatch?.score ?? Int.max {
									bestMatch = (score: componentScore, component: component, usageComponent: usageComponent)
								}
							}
						}
						
						
						if let (compScore, comp, usageComp) = bestMatch {
							score += compScore
							availableComponents.remove(at: availableComponents.index(of: comp)!)
							availableUsageComponents.remove(at: availableUsageComponents.index(of: usageComp)!)
						}
					}
					
					
					let args = usageComponents.filter {
						$0 == "*" || $0 == "..."
					}
					for _ in args {
						if !availableComponents.isEmpty {
							availableComponents.removeFirst()
						}
					}
					
					for component in (availableComponents + availableUsageComponents) {
						score += component.characters.count
					}
					
					commandScores[usage] = score
				}
			}
		}
		
		
		
		
		var lowest: (command: String, score: Int)?
		for (command, score) in commandScores {
			if score <= command.characters.count/2 && score < (lowest?.score ?? Int.max) {
				lowest = (command, score)
			}
		}
		
		if let (command, _) = lowest {
			room.postReply("Unrecognized command `\(components.joined(separator: " "))`; did you mean `\(command)`?", to: message)
		}
	}
	
	open func processMessage(_ room: ChatRoom, message: ChatMessage, isEdit: Bool) {
		let lowercase = message.content.lowercased()
		
		let shortName = name.characters[name.characters.startIndex..<name.characters.index(name.characters.startIndex, offsetBy: min(name.characters.count, requiredCharacters))]
		if pendingStopAction == .run && lowercase.hasPrefix(shortName.lowercased()) {
			//do a more precise check so names like @FirstStep won't cause the bot to respond
			let name = self.name.lowercased().unicodeScalars
			
			let msg = lowercase.unicodeScalars
			
			for i in 0...name.count {
				if i >= msg.count {
					if i > 4 {
						break
					}
					else {
						return
					}
				}
				let messageChar = msg[msg.index(msg.startIndex, offsetBy: i)]
				if i < name.count {
					let nameChar = name[name.index(name.startIndex, offsetBy: i)]
					if !CharacterSet.alphanumerics.contains(nameChar) {
						break
					}
					if nameChar != messageChar {
						return
					}
				}
				else {
					if CharacterSet.alphanumerics.contains(messageChar) {
						return
					}
				}
				
			}
			handleCommand(message)
		}
	}
	
	open func stop(_ stopAction: StopAction) {
		pendingStopAction = stopAction
		if self.runningCommands.isEmpty {
			shutdownHandler(self.pendingStopAction == .reboot, self.pendingStopAction == .update)
		}
	}
	
	public init(_ room: ChatRoom, commands: [Command.Type]) {
		self.room = room
		self.commands = commands
	}
}
