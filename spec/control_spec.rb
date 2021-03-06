require_relative '../control'


describe Control do
  let(:joystick) { double 'joystick' }
  let(:neutral_pose) { double 'neutral_pose' }
  let(:serial_client) { double 'serial_client' }
  let(:pose) { double 'pose' }
  let(:target_radians) { double 'target_radians' }
  let(:target_degrees) { double 'target_degrees' }
  let(:control) { Control.new 1, 1 }

  before :each do
    allow(Joystick).to receive(:new).and_return joystick
    allow(joystick).to receive :update
    allow(joystick).to receive(:axis).and_return({})
    allow(joystick).to receive(:button).and_return({})
    allow(SerialClient).to receive(:new).and_return serial_client
    allow(serial_client).to receive :target
    allow(serial_client).to receive(:ready?).and_return true
    allow(serial_client).to receive(:time_remaining).and_return 5
    allow(serial_client).to receive(:time_required).and_return 11
    allow(neutral_pose).to receive(:*).and_return pose
    allow(Kinematics).to receive(:forward).and_return neutral_pose
    allow(Kinematics).to receive(:inverse).and_return(Vector[target_radians])
  end

  describe :initialize do
    it 'should initialize the joystick' do
      expect(Joystick).to receive :new
      Control.new
    end

    it 'should initialize serial communication' do
      expect(SerialClient).to receive(:new).with '/dev/ttyUSB0', 115200
      Control.new 1, 1, '/dev/ttyUSB0', 115200
    end

    it 'should start with a zero position offset' do
      expect(Control.new.position).to eq Vector[0, 0, 0, 0, 0, 0, 0]
    end

    it 'should determine the forward kinematics of the neutral configuration' do
      expect(Kinematics).to receive(:forward).with Vector[0, 0, 0, 0, 0, 0]
      Control.new
    end
  end

  describe :adapt do
    it 'should map zero to zero' do
      expect(control.adapt(0)).to eq 0
    end

    it 'should map 32768 to one' do
      expect(control.adapt(32768)).to eq 1
    end

    it 'should use a dead zone' do
      expect(control.adapt(Control::DEADZONE)).to eq 0
    end

    it 'should scale linearly above dead zone' do
      expect(control.adapt(2 * Control::DEADZONE)).to be_between(0, 1).exclusive
    end

    it 'should map -32768 to one' do
      expect(control.adapt(-32768)).to eq -1
    end

    it 'should use a negative dead zone' do
      expect(control.adapt(-Control::DEADZONE)).to eq 0
    end

    it 'should scale linearly below the negative dead zone' do
      expect(control.adapt(-2 * Control::DEADZONE)).to be_between(-1, 0).exclusive
    end
  end

  describe :pose_matrix do
    it 'should create a translation matrix' do
      expect(control.pose_matrix(Vector[2, 3, 5, 0, 0, 0, 0])).
        to eq Matrix[[1, 0, 0, 2], [0, 1, 0, 3], [0, 0, 1, 5], [0, 0, 0, 1]]
    end

    it 'should perform rotations' do
      expect(control.pose_matrix(Vector[2, 3, 5, 0.1, 0.2, 0.3, 0])).
        to be_within(1e-6).of Matrix.translation(2, 3, 5) * Matrix.rotate_y(0.1) * Matrix.rotate_x(0.2) * Matrix.rotate_z(0.3)
    end
  end

  describe :degrees do
    it 'should convert angles from radians to degrees' do
      expect(control.degrees([0, Math::PI, 2 * Math::PI])).to eq [0, 180, 360]
    end
  end

  describe :update do
    let(:pose_offset) { double 'pose_offset' }
    before :each do
      allow(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2
      allow(control).to receive(:pose_matrix).and_return pose_offset
      allow(control).to receive(:degrees).and_return target_degrees
    end

    it 'should update the joystick' do
      expect(joystick).to receive :update
      control.update
    end

    it 'should convert positional changes' do
      expect(joystick).to receive(:axis).and_return({0 => 2, 4 => 3, 1 => 5, 3 => 7})
      expect(control).to receive(:adapt).with(2).ordered.and_return 0.2
      expect(control).to receive(:adapt).with(3).ordered.and_return 0.5
      expect(control).to receive(:adapt).with(5).ordered.and_return 1.0
      expect(control).to receive(:adapt).with(7).ordered.and_return 1.2
      control.update
    end

    it 'should apply the positional offset' do
      expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0
      control.update
      expect(control.position).to eq Vector[0.2, 0.5, -1.0, 0, 0, 1.2, 0]
    end

    it 'should accumulate the positional offset' do
      expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0, 0.2, 0.5, 1.0, 1.2, 0, 0
      control.update
      control.update
      expect(control.position).to eq Vector[0.4, 1.0, -2.0, 0, 0, 2.4, 0]
    end

    it 'should use the specified speed values' do
      control = Control.new 2, 4
      allow(control).to receive(:degrees).and_return target_degrees
      expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0
      control.update
      expect(control.position).to eq Vector[0.4, 1.0, -2.0, 0, 0, 4.8, 0]
    end

    it 'should use the specified time step' do
      expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0
      control.update 2
      expect(control.position).to eq Vector[0.4, 1.0, -2.0, 0, 0, 2.4, 0]
    end

    it 'should determine the pose matrix' do
      expect(control).to receive(:pose_matrix).with Vector[0.2, 0.5, -1.0, 0, 0, 1.2, 0]
      control.update
    end

    it 'should invoke the inverse kinematics' do
      expect(Kinematics).to receive(:inverse).with pose
      control.update
    end

    it 'should convert the angles to degrees' do
      expect(control).to receive(:degrees).with([target_radians, 0])
      control.update
    end

    it 'should target the dessired configuration' do
      expect(serial_client).to receive(:target).with *target_degrees
      control.update
    end

    it 'should only target the desired configuration if the microcontroller is ready' do
      expect(serial_client).to receive(:ready?).and_return false
      expect(serial_client).to_not receive :target
      control.update
    end

    it 'should only submit a target if it requires more than twice the remaining time of the current target' do
      expect(serial_client).to receive(:time_remaining).and_return 5
      expect(serial_client).to receive(:time_required).with(*target_degrees).and_return 9
      expect(serial_client).to_not receive :target
      control.update
    end

    it 'should not submit a target if the inverse kinematics does not return a solution' do
      allow(Kinematics).to receive(:inverse).and_return nil
      expect(serial_client).to_not receive :target
      control.update
    end

    context 'when the A button is pressed' do
      before :each do
        allow(joystick).to receive(:button).and_return({0 => true})
      end

      it 'should convert rotational changes' do
        expect(joystick).to receive(:axis).and_return({4 => 2, 0 => 3, 1 => 5, 3 => 7, 5 => 11, 2 => 13})
        expect(control).to receive(:adapt).with(2).ordered.and_return 0.2
        expect(control).to receive(:adapt).with(3).ordered.and_return 0.5
        expect(control).to receive(:adapt).with(5).ordered.and_return 1.0
        expect(control).to receive(:adapt).with(7).ordered.and_return 1.2
        expect(control).to receive(:adapt).with(11).ordered.and_return 0
        expect(control).to receive(:adapt).with(13).ordered.and_return 0
        control.update
      end

      it 'should apply the rotational offset' do
        expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0
        control.update
        expect(control.position).to eq Vector[0, 0.2, 0, -0.5, 1.0, 1.2, 0]
      end

      it 'should use the specified speed values' do
        control = Control.new 2, 4
        allow(control).to receive(:degrees).and_return target_degrees
        expect(control).to receive(:adapt).and_return 0.2, 0.5, 1.0, 1.2, 0, 0
        control.update
        expect(control.position).to eq Vector[0, 0.4, 0, -2.0, 4.0, 4.8, 0]
      end

    end

    it 'should update the gripper' do
      allow(joystick).to receive(:axis).and_return({5 => 2})
      allow(control).to receive(:adapt).and_return 0
      expect(control).to receive(:adapt).and_return 0, 0, 0, 0, 2, 0
      control.update
      expect(control.position).to eq Vector[0, 0, 0, 0, 0, 0, 2]
    end

    it 'should use the difference of two axes for the gripper' do
      allow(joystick).to receive(:axis).and_return({5 => 2, 2 => 2})
      expect(control).to receive(:adapt).and_return 0, 0, 0, 0, 2, 2
      control.update
      expect(control.position).to eq Vector[0, 0, 0, 0, 0, 0, 0]
    end

    it 'should convert the gripper angle to degrees' do
      allow(joystick).to receive(:axis).and_return({5 => 2})
      expect(control).to receive(:adapt).and_return 0, 0, 0, 0, 2, 0
      expect(control).to receive(:degrees).with([target_radians, 2])
      control.update
    end
  end

  describe :quit? do
    it 'should return false by default' do
      expect(control.quit?).to be false
    end

    it 'should return true if the X button is pressed' do
      expect(joystick).to receive(:button).and_return({2 => true})
      expect(control.quit?).to be true
    end
  end
end
